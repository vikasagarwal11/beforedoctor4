import { buildApp } from "./app.js";

const { app, env } = await buildApp();

await app.listen({ port: env.PORT, host: "0.0.0.0" });
