const { format } = require("path");

function byteCount(s) {
  return encodeURI(s).split(/%..|./).length - 1;
}

exports("HandleHttpRequest", (dest, callback, method, data, headers) => {
  emit(
    "SonoranCMS::core:writeLog",
    "debug",
    "[http] to: " + dest + " - data: " + dest,
    JSON.stringify(data)
  );
  const urlObj = url.parse(dest);
  const requestMethod = String(method || "GET").toUpperCase();
  const requestHeaders = headers || {};
  const options = {
    hostname: urlObj.hostname,
    path: urlObj.path || urlObj.pathname,
    method: requestMethod,
    headers: requestHeaders,
  };
  if (urlObj.hostname === "localhost") options.port = urlObj.port;

  const methodsWithBody = new Set(["POST", "PUT", "PATCH", "DELETE"]);
  if (methodsWithBody.has(requestMethod)) {
    options.headers["Content-Type"] = "application/json";
  } else if (requestMethod != "GET") {
    console.error(
      "Invalid request. Only GET/POST/PUT/PATCH/DELETE supported. Method: " +
        requestMethod
    );
    callback(500, "", {});
    return;
  }

  options.headers["X-SonoranCMS-Version"] = GetResourceMetadata(
    GetCurrentResourceName(),
    "version",
    0
  );
  //console.debug("send to: " + dest);
  const httpModule = urlObj.protocol === "https:" ? https : http;
  const req = httpModule.request(options, (res) => {
    let output = "";
    res.on("data", (d) => {
      output += d.toString();
    }),
      res.on("end", () => {
        callback(res.statusCode, output, res.headers);
      });
  });

  req.on("error", (error) => {
    let ignore_ids = ["EAI_AGAIN", "ETIMEOUT", "ENOTFOUND"];
    if (!ignore_ids.includes(error.code))
      console.debug("HTTP error caught: " + JSON.stringify(error));
    callback(error.errono, {}, {});
  });
  if (methodsWithBody.has(requestMethod)) {
    req.write(data);
  }
  req.end();
});
