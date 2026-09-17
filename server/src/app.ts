import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import Fastify from 'fastify';

export function buildApp() {
  const app = Fastify({ logger: true });

  app.register(helmet);
  app.register(cors, { origin: false });

  app.get('/health', async () => ({
    status: 'ok',
    service: 'todolist-server',
    timestamp: new Date().toISOString(),
  }));

  return app;
}
