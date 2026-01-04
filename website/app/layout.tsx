import type { Metadata } from 'next'
import { Inter, Space_Grotesk } from 'next/font/google'
import './globals.css'

const inter = Inter({ 
  subsets: ['latin', 'cyrillic'],
  variable: '--font-inter',
})

const spaceGrotesk = Space_Grotesk({ 
  subsets: ['latin'],
  variable: '--font-space-grotesk',
})

export const metadata: Metadata = {
  title: 'Расписание - ЧТОТиБ и ЗАБГК',
  description: 'Расписание занятий для студентов ЧТОТиБ и ЗАБГК. Быстрый доступ к актуальному расписанию.',
  keywords: 'расписание, ЧТОТиБ, ЗАБГК, занятия, студенты',
  viewport: 'width=device-width, initial-scale=1, maximum-scale=5',
  themeColor: '#000000',
  openGraph: {
    title: 'Расписание - ЧТОТиБ и ЗАБГК',
    description: 'Расписание занятий для студентов',
    type: 'website',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="ru">
      <body className={`${inter.variable} ${spaceGrotesk.variable}`}>
        {children}
      </body>
    </html>
  )
}

