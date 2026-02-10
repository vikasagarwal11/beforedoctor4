import pino from "pino";

export function createLogger(level: string) {
  const isDev = process.env.NODE_ENV !== "production";
  return pino({
    level,
    transport: isDev
      ? {
          target: "pino-pretty",
          options: { colorize: true, translateTime: "SYS:standard" }
        }
      : undefined
  });
}
