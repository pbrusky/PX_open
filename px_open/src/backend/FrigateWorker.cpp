#include "FrigateWorker.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>

#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkAccessManager>

#include <QDebug>

FrigateWorker::FrigateWorker(QObject* parent)
    : QObject(parent),
      m_net(new QNetworkAccessManager(this))
{
}

void FrigateWorker::setServer(const QString& url)
{
    m_serverUrl = url;
    qDebug() << "[Worker] Server set to:" << m_serverUrl;
}

//
// ⭐ Module information is handled entirely in FrigateAPI.
// This prevents QML from calling a missing function.
//
void FrigateWorker::loadModuleInformation()
{
    // No-op
}

void FrigateWorker::loadCameras()
{
    if (m_serverUrl.isEmpty()) {
        qWarning() << "[Worker] Cannot load cameras: server URL is empty";
        emit camerasLoaded(QByteArray());
        return;
    }

    const QString endpoint = m_serverUrl + "/api/config";
    qDebug() << "[Worker] Requesting cameras from:" << endpoint;

    QUrl url(endpoint);
    QNetworkRequest req(url);

    // ⭐ MSVC-safe explicit call
    QNetworkReply* reply = m_net->QNetworkAccessManager::get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        QByteArray data = reply->readAll();
        reply->deleteLater();

        if (data.isEmpty()) {
            qWarning() << "[Worker] Empty response from server";
            emit camerasLoaded(QByteArray());
            return;
        }

        // Validate JSON before forwarding
        QJsonParseError err;
        QJsonDocument doc = QJsonDocument::fromJson(data, &err);

        if (err.error != QJsonParseError::NoError) {
            qWarning() << "[Worker] JSON parse error:" << err.errorString();
            emit camerasLoaded(QByteArray());
            return;
        }

        qDebug() << "[Worker] Loaded config JSON (" << data.size() << " bytes )";

        // ⭐ Send RAW JSON to FrigateAPI (FrigateAPI does all parsing)
        emit camerasLoaded(data);
    });
}
