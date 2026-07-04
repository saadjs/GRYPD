import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';

export default defineConfig({
  plugins: [react()],
  base: '/',
  build: {
    outDir: 'build',
    rollupOptions: {
      input: {
        home: resolve(__dirname, 'index.html'),
        features: resolve(__dirname, 'features.html'),
        dataSource: resolve(__dirname, 'data-source.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        support: resolve(__dirname, 'support.html'),
      },
    },
  },
});
