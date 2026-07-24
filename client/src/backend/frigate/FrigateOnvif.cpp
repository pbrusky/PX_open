#include "FrigateOnvif.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QSslConfiguration>
#include <QSslSocket>

FrigateOnvif::FrigateOnvif(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this))
{
}

void FrigateOnvif::setModuleServer(const QString& server)
{
    m_moduleServer = server;
}

QVariantList FrigateOnvif::getOnvifProgress() const
{
    return m_onvifProgress;
}

//
// ⭐ ONVIF DISCOVERY (silent)
//
void FrigateOnvif::discoverOnvif(const QString& username, const QString& password)
{
    if (m_moduleServer.isEmpty()) {
        emit onvifDevicesDiscovered(QVariantList());
        return;
    }

    m_onvifProgress.clear();

    const QUrl url(m_moduleServer + "/api/onvifDiscover");

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
    ssl.setPeerVerifyMode(QSslSocket::VerifyNone);
    ssl.setProtocol(QSsl::TlsV1_2OrLater);
    req.setSslConfiguration(ssl);

    QJsonObject obj;
    obj["username"] = username;
    obj["password"] = password;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::sslErrors, reply,
            [reply](const QList<QSslError>&) {
        reply->ignoreSslErrors();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {

        if (reply->error() != QNetworkReply::NoError) {
            reply->deleteLater();
            emit onvifDevicesDiscovered(QVariantList());
            return;
        }

        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isObject()) {
            emit onvifDevicesDiscovered(QVariantList());
            return;
        }

        QJsonArray arr = doc.object().value("devices").toArray();
        QVariantList finalList;

        for (const QJsonValue& v : arr) {
            QJsonObject o = v.toObject();
            QVariantMap dev;

            dev["address"]      = o.value("address").toString();
            dev["manufacturer"] = o.value("manufacturer").toString();
            dev["model"]        = o.value("model").toString();
            dev["username"]     = o.value("username").toString();
            dev["password"]     = o.value("password").toString();
            dev["rtsp"]         = o.value("rtsp").toString();

            finalList.append(dev);
        }

        emit onvifDevicesDiscovered(finalList);
    });
}

//
// ⭐ GET RTSP FROM ONVIF (silent)
//
void FrigateOnvif::getRtsp(const QString& ip, const QString& username, const QString& password)
{
    if (m_moduleServer.isEmpty()) {
        emit rtspResolved("");
        return;
    }

    const QUrl url(m_moduleServer + "/api/getRtsp");

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QSslConfiguration ssl = QSslConfiguration::defaultConfiguration();
    ssl.setPeerVerifyMode(QSslSocket::VerifyNone);
    ssl.setProtocol(QSsl::TlsV1_2OrLater);
    req.setSslConfiguration(ssl);

    QJsonObject obj;
    obj["ip"] = ip;
    obj["username"] = username;
    obj["password"] = password;

    QNetworkReply* reply = m_net->post(req, QJsonDocument(obj).toJson());

    connect(reply, &QNetworkReply::sslErrors, reply,
            [reply](const QList<QSslError>&) {
        reply->ignoreSslErrors();
    });

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {

        QByteArray data = reply->readAll();
        reply->deleteLater();

        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (!doc.isObject()) {
            emit rtspResolved("");
            return;
        }

        QString rtsp = doc.object().value("rtsp").toString();
        emit rtspResolved(rtsp);
    });
}
