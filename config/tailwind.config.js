/**
 * Medietilsynet Design System - Tailwind Configuration
 * Extracted from: https://www.medietilsynet.no/
 * Date: 2025-12-16
 * 
 * Design tokens extracted using Dembrandt and converted to Tailwind theme.
 */

module.exports = {
  darkMode: 'class',
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}',
    './app/assets/stylesheets/**/*.css'
  ],
  theme: {
    extend: {
      colors: {
        // Medietilsynet Brand Colors
        medietilsynet: {
          // Primary brand blue
          'brand-blue': '#0c5da4',
          'brand-blue-dark': '#094a85',
          'brand-blue-light': '#1a6fb8',
          
          // Interactive blue (links)
          'blue': '#0000ee',
          'blue-hover': '#0c5da4',
          
          // Text colors
          'text-primary': '#393939',
          'text-secondary': '#808080',
          'text-black': '#000000',
          
          // Borders
          'border-light': '#dddddd',
          'border-medium': '#808080',
        },
        
        // Semantic color aliases
        primary: {
          DEFAULT: '#0c5da4',
          hover: '#094a85',
          light: '#1a6fb8',
        },
        secondary: {
          DEFAULT: '#393939',
          light: '#808080',
        },
        link: {
          DEFAULT: '#0000ee',
          hover: '#0c5da4',
        },
      },
      
      fontFamily: {
        // Medietilsynet Typography (using Inter as Graphik Web alternative)
        'graphik': ['Inter', 'system-ui', 'sans-serif'],
        'merriweather': ['Merriweather', 'Georgia', 'serif'],
        'play': ['Inter', 'sans-serif'],
        
        // Semantic font aliases
        sans: ['Inter', 'system-ui', 'sans-serif'],
        serif: ['Merriweather', 'Georgia', 'serif'],
      },
      
      fontSize: {
        // Medietilsynet Typography Scale
        'base': ['18px', { lineHeight: '1.6' }],
        'heading-1': ['18px', { lineHeight: '1.4', fontWeight: '700' }],
        'link': ['18px', { lineHeight: '1.4', fontWeight: '400' }],
        'button': ['18px', { lineHeight: '1.56', fontWeight: '400' }],
      },
      
      spacing: {
        // Medietilsynet 8px-based spacing system
        '0.5': '1px',   // hairline
        '1.5': '3px',   // minimal
        '2.5': '5px',   // small
        '3.5': '7px',   // compact
        // Standard Tailwind continues: 4 = 16px, 5 = 20px, etc.
      },
      
      borderRadius: {
        // Medietilsynet Border Radius
        'sm': '3px',      // subtle rounding
        'pill': '35px',   // pill-shaped elements
      },
      
      borderWidth: {
        DEFAULT: '1px',
      },
      
      borderColor: theme => ({
        DEFAULT: theme('colors.medietilsynet.border-light'),
        'light': theme('colors.medietilsynet.border-light'),
        'medium': theme('colors.medietilsynet.border-medium'),
      }),
      
      screens: {
        // Medietilsynet Responsive Breakpoints
        'mobile': '480px',
        'tablet': '768px',
        'desktop': '1024px',
        'lg-desktop': '1280px',
        'xl-desktop': '1520px',
      },
    },
  },
  plugins: []
}
