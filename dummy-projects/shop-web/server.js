const http = require("node:http");

const page = `<!doctype html>
<html>
  <head><meta charset="utf-8"><title>Shop Web</title></head>
  <body>
    <h1>Shop Web</h1>
    <p>Dummy storefront served through portless.</p>
  </body>
</html>
`;

http
  .createServer((req, res) => {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(page);
  })
  .listen(process.env.PORT, () => console.log(`shop-web listening on ${process.env.PORT}`));
