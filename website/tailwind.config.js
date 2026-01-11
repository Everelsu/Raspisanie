/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // Light theme
        'light-bg': '#FFFFFF',
        'light-surface': '#FFFFFF',
        'light-text': '#000000',
        'light-text-secondary': '#757575',
        
        // Dark theme
        'dark-bg': '#000000',
        'dark-surface': '#000000',
        'dark-text': '#FFFFFF',
        'dark-text-secondary': '#AAAAAA',
        
        // Purple theme
        'purple-bg': '#20122E',
        'purple-surface': '#2A1C40',
        'purple-primary': '#6750A4',
        'purple-text': '#FFFFFF',
        'purple-text-secondary': '#B794D4',
        
        // Green theme
        'green-bg': '#0A1A0A',
        'green-surface': '#1A2A1A',
        'green-primary': '#4CAF50',
        'green-text': '#FFFFFF',
        'green-text-secondary': '#81C784',
        
        // Halloween theme
        'halloween-bg': '#1A0A00',
        'halloween-surface': '#2A1510',
        'halloween-primary': '#FF7B4A',
        'halloween-text': '#FFFFFF',
        'halloween-text-secondary': '#FFAA7F',
        
        // Nothing theme
        'nothing-bg': '#0F0000',
        'nothing-surface': '#1A0A0A',
        'nothing-primary': '#FF3333',
        'nothing-text': '#FFFFFF',
        'nothing-text-secondary': '#FF6666',
        
        // New Year theme
        'newyear-bg': '#0A1A0A',
        'newyear-surface': '#1A2A1A',
        'newyear-primary': '#2E7D32',
        'newyear-text': '#FFFFFF',
        'newyear-text-secondary': '#81C784',
      },
    },
  },
  plugins: [],
}



