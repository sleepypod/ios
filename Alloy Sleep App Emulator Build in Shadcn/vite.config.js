import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import svgr from 'vite-plugin-svgr'

export default defineConfig(({ mode, command }) => {
  const env = loadEnv(mode, process.cwd(), '')

  return {
    plugins: [
      svgr({
        svgrOptions: {
          typescript: false
        }
      }),
      react()
    ],
    base: './',
    build: {
      minify: false,
      cssMinify: false,
      sourcemap: false,
      target: 'esnext',
      rollupOptions: {
        treeshake: false,
        output: {
          manualChunks: undefined,
          inlineDynamicImports: true
        }
      },
      reportCompressedSize: false,
      chunkSizeWarningLimit: 10000,
      assetsDir: ''
    },
    esbuild: {
      target: 'esnext',
      minify: false
    },
    optimizeDeps: {
      force: true,
      include: ['react', 'react-dom']
    }
  }
})
