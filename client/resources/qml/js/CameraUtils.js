.pragma library

function parseRtspCredentials(url) {
    if (!url || url.indexOf("rtsp://") !== 0)
        return { user: "", pass: "" }

    var after = url.substring(7) // strip "rtsp://"
    var at = after.indexOf("@")
    if (at < 0)
        return { user: "", pass: "" }

    var authPart = after.substring(0, at)
    var colon = authPart.indexOf(":")
    if (colon < 0)
        return { user: "", pass: "" }

    return {
        user: authPart.substring(0, colon),
        pass: authPart.substring(colon + 1)
    }
}