const express = require("express");
const app = express();
app.get("/", (_, res) => res.send("built by buildcat 🐱\n"));
app.listen(3000, () => console.log("listening on :3000"));
