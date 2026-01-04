/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Для Vercel используем стандартный режим (не standalone)
  // Standalone используется для Docker контейнеров
  // output: 'standalone', // Раскомментируйте только если деплоите в Docker
  
  // Разрешаем внешние изображения и ресурсы
  images: {
    unoptimized: true,
  },
  
  // Настройки для работы с внешними API
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          {
            key: 'X-Content-Type-Options',
            value: 'nosniff',
          },
          {
            key: 'X-Frame-Options',
            value: 'DENY',
          },
          {
            key: 'X-XSS-Protection',
            value: '1; mode=block',
          },
        ],
      },
    ];
  },
  
  // Отключаем проверку типов во время сборки (ускоряет деплой)
  typescript: {
    ignoreBuildErrors: false,
  },
  
  // Отключаем проверку ESLint во время сборки (если нужно)
  eslint: {
    ignoreDuringBuilds: false,
  },
}

module.exports = nextConfig



