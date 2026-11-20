import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Local API calls go through this server at /api, so the dashboard works the
// same from this laptop or another device on the network.
// Set API_PROXY_TARGET=https://localhost:8000 if the API runs HTTPS.
const target = process.env.API_PROXY_TARGET || 'http://localhost:8000';
const proxy = {
  '/api': {
    target,
    changeOrigin: true,
    rewrite: (path) => path.replace(/^\/api/, ''),
  },
};

export default defineConfig({
  plugins: [react()],
  server: { proxy },
  preview: { proxy },
});
