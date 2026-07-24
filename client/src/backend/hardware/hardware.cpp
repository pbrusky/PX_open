#include "D3D11Renderer.h"
#include <QOpenGLFramebufferObject>
#include <QOpenGLFunctions>
#include <QDebug>

extern "C" {
#include <libavutil/pixfmt.h>
}

static const char* g_vsCode = R"(
struct VSInput {
    float2 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

struct PSInput {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

PSInput VSMain(VSInput input)
{
    PSInput output;
    output.pos = float4(input.pos, 0.0f, 1.0f);
    output.uv  = input.uv;
    return output;
}
)";

// NV12 YUV → RGB shader (matches what you posted)
static const char* g_psCode = R"(
Texture2D texY  : register(t0);   // R8_UNORM
Texture2D texUV : register(t1);   // R8G8_UNORM
SamplerState samp : register(s0);

float4 PSMain(float2 uv : TEXCOORD0) : SV_TARGET
{
    float y  = texY.Sample(samp, uv).r;

    float2 uvSample = texUV.Sample(samp, uv).rg;
    float u = uvSample.x - 0.5f;
    float v = uvSample.y - 0.5f;

    float r = y + 1.402f * v;
    float g = y - 0.344f * u - 0.714f * v;
    float b = y + 1.772f * u;

    return float4(r, g, b, 1.0f);
}
)";

D3D11Renderer::D3D11Renderer(FrameQueue* queue)
    : m_queue(queue)
{
    qDebug() << "D3D11Renderer: constructor (hardware NV12)";
}

D3D11Renderer::~D3D11Renderer()
{
    qDebug() << "D3D11Renderer: destructor";
}

QOpenGLFramebufferObject* D3D11Renderer::createFramebufferObject(const QSize& size)
{
    m_size = size;

    QOpenGLFramebufferObjectFormat fmt;
    fmt.setAttachment(QOpenGLFramebufferObject::CombinedDepthStencil);
    return new QOpenGLFramebufferObject(size, fmt);
}

bool D3D11Renderer::initD3D(const QSize& size)
{
    if (m_initialized)
        return true;

    qDebug() << "D3D11Renderer: Initializing D3D11 (NV12)";

    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

    D3D_FEATURE_LEVEL fl;
    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        flags,
        nullptr,
        0,
        D3D11_SDK_VERSION,
        &m_device,
        &fl,
        &m_context
    );

    if (FAILED(hr)) {
        qWarning() << "D3D11Renderer: Failed to create D3D11 device";
        return false;
    }

    // Render target
    D3D11_TEXTURE2D_DESC rtDesc = {};
    rtDesc.Width = size.width();
    rtDesc.Height = size.height();
    rtDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    rtDesc.ArraySize = 1;
    rtDesc.MipLevels = 1;
    rtDesc.SampleDesc.Count = 1;
    rtDesc.BindFlags = D3D11_BIND_RENDER_TARGET;

    hr = m_device->CreateTexture2D(&rtDesc, nullptr, &m_renderTarget);
    if (FAILED(hr)) {
        qWarning() << "D3D11Renderer: Failed to create render target";
        return false;
    }

    hr = m_device->CreateRenderTargetView(m_renderTarget.Get(), nullptr, &m_rtv);
    if (FAILED(hr)) {
        qWarning() << "D3D11Renderer: Failed to create RTV";
        return false;
    }

    // Shaders
    ComPtr<ID3DBlob> vsBlob, psBlob, errBlob;

    hr = D3DCompile(g_vsCode, strlen(g_vsCode), nullptr, nullptr, nullptr,
                    "VSMain", "vs_5_0", 0, 0, &vsBlob, &errBlob);

    hr = D3DCompile(g_psCode, strlen(g_psCode), nullptr, nullptr, nullptr,
                    "PSMain", "ps_5_0", 0, 0, &psBlob, &errBlob);

    m_device->CreateVertexShader(vsBlob->GetBufferPointer(), vsBlob->GetBufferSize(), nullptr, &m_vs);
    m_device->CreatePixelShader(psBlob->GetBufferPointer(), psBlob->GetBufferSize(), nullptr, &m_ps);

    // Input layout
    D3D11_INPUT_ELEMENT_DESC layout[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0},
        {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 8, D3D11_INPUT_PER_VERTEX_DATA, 0}
    };

    m_device->CreateInputLayout(layout, 2,
                                vsBlob->GetBufferPointer(),
                                vsBlob->GetBufferSize(),
                                &m_inputLayout);

    // Fullscreen quad
    struct Vertex { float pos[2]; float uv[2]; };
    Vertex quad[4] = {
        {{-1, -1}, {0, 1}},
        {{ 1, -1}, {1, 1}},
        {{-1,  1}, {0, 0}},
        {{ 1,  1}, {1, 0}}
    };

    D3D11_BUFFER_DESC vbDesc = {};
    vbDesc.ByteWidth = sizeof(quad);
    vbDesc.Usage = D3D11_USAGE_DEFAULT;
    vbDesc.BindFlags = D3D11_BIND_VERTEX_BUFFER;

    D3D11_SUBRESOURCE_DATA vbData = {};
    vbData.pSysMem = quad;

    m_device->CreateBuffer(&vbDesc, &vbData, &m_vertexBuffer);

    // Sampler
    D3D11_SAMPLER_DESC sampDesc = {};
    sampDesc.Filter = D3D11_FILTER_MIN_MAG_LINEAR_MIP_POINT;
    sampDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.ComparisonFunc = D3D11_COMPARISON_NEVER;
    sampDesc.MinLOD = 0;
    sampDesc.MaxLOD = D3D11_FLOAT32_MAX;

    m_device->CreateSamplerState(&sampDesc, &m_sampler);

    m_initialized = true;
    return true;
}

void D3D11Renderer::uploadFrame(AVFrame* frame)
{
    if (!frame)
        return;

    // Expect AV_PIX_FMT_NV12 from hardware decode
    if (frame->format != AV_PIX_FMT_NV12) {
        qWarning() << "D3D11Renderer: expected NV12, got format" << frame->format;
        return;
    }

    int w = frame->width;
    int h = frame->height;

    auto uploadPlane = [&](uint8_t* data, int stride, int width, int height,
                           ComPtr<ID3D11Texture2D>& tex,
                           ComPtr<ID3D11ShaderResourceView>& srv,
                           DXGI_FORMAT fmt)
    {
        if (!tex) {
            D3D11_TEXTURE2D_DESC desc = {};
            desc.Width = width;
            desc.Height = height;
            desc.Format = fmt;
            desc.ArraySize = 1;
            desc.MipLevels = 1;
            desc.SampleDesc.Count = 1;
            desc.Usage = D3D11_USAGE_DYNAMIC;
            desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
            desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

            m_device->CreateTexture2D(&desc, nullptr, &tex);
            m_device->CreateShaderResourceView(tex.Get(), nullptr, &srv);
        }

        D3D11_MAPPED_SUBRESOURCE map;
        m_context->Map(tex.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &map);

        uint8_t* dst = (uint8_t*)map.pData;
        for (int y = 0; y < height; y++) {
            memcpy(dst + y * map.RowPitch, data + y * stride, width * (fmt == DXGI_FORMAT_R8G8_UNORM ? 2 : 1));
        }

        m_context->Unmap(tex.Get(), 0);
    };

    // NV12: data[0] = Y (w x h), data[1] = interleaved UV (w/2 x h/2, 2 bytes per pixel)
    uploadPlane(frame->data[0], frame->linesize[0], w,     h,     m_texY,  m_srvY,  DXGI_FORMAT_R8_UNORM);
    uploadPlane(frame->data[1], frame->linesize[1], w / 2, h / 2, m_texUV, m_srvUV, DXGI_FORMAT_R8G8_UNORM);
}

void D3D11Renderer::drawFrame()
{
    m_context->OMSetRenderTargets(1, m_rtv.GetAddressOf(), nullptr);

    float clearColor[4] = {0, 0, 0, 1};
    m_context->ClearRenderTargetView(m_rtv.Get(), clearColor);

    UINT stride = sizeof(float) * 4;
    UINT offset = 0;

    m_context->IASetInputLayout(m_inputLayout.Get());
    m_context->IASetVertexBuffers(0, 1, m_vertexBuffer.GetAddressOf(), &stride, &offset);
    m_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);

    m_context->VSSetShader(m_vs.Get(), nullptr, 0);
    m_context->PSSetShader(m_ps.Get(), nullptr, 0);

    ID3D11ShaderResourceView* srvs[2] = {m_srvY.Get(), m_srvUV.Get()};
    m_context->PSSetShaderResources(0, 2, srvs);
    m_context->PSSetSamplers(0, 1, m_sampler.GetAddressOf());

    m_context->Draw(4, 0);
}

void D3D11Renderer::render()
{
    if (!m_initialized)
        initD3D(m_size);

    AVFrame* frame = m_queue ? m_queue->pop() : nullptr;
    if (frame) {
        uploadFrame(frame);
        av_frame_free(&frame);
    }

    drawFrame();
}
