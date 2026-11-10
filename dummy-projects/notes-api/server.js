const http = require("node:http");

const notes = [
  { id: 1, title: "Buy milk" },
  { id: 2, title: "Ship the menu bar app" },
];

http
  .createServer((req, res) => {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ service: "notes-api", path: req.url, notes }));
  })
  .listen(process.env.PORT, () => console.log(`notes-api listening on ${process.env.PORT}`));
