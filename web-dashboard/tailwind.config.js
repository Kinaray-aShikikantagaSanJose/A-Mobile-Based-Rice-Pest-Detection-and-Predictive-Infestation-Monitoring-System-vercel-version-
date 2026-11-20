/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      // Same palette as the mobile app (lib/theme.dart).
      colors: {
        brand: {
          50: '#F1F8F3',
          100: '#D8F3DC',
          200: '#B7E4C7',
          600: '#40916C',
          700: '#2D6A4F',
          800: '#245A42',
          900: '#1B4332',
          950: '#0F2A1F',
        },
        // Palay Patrol logo colours (grain gold, leaf green).
        gold: {
          300: '#F5D66B',
          400: '#EDC531',
          500: '#E0B409',
          600: '#C29B06',
        },
        leaf: '#64A450',
        canvas: '#FAF8F5',
        line: '#E5E0D8',
        ink: '#1B4332',
        ink2: '#5C6B5E',
        muted: '#8E9E90',
        low: '#10B981',
        medium: '#E67E22',
        high: '#E63946',
      },
      fontFamily: {
        sans: ['Inter', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
      },
      keyframes: {
        'fade-up': {
          from: { opacity: '0', transform: 'translateY(12px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        'fade-in': { from: { opacity: '0' }, to: { opacity: '1' } },
        float: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-8px)' },
        },
        'pulse-ring': {
          '0%': { transform: 'scale(0.9)', opacity: '0.55' },
          '100%': { transform: 'scale(1.6)', opacity: '0' },
        },
        indeterminate: {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(250%)' },
        },
        shake: {
          '0%, 100%': { transform: 'translateX(0)' },
          '20%, 60%': { transform: 'translateX(-6px)' },
          '40%, 80%': { transform: 'translateX(6px)' },
        },
        'slide-in': { from: { transform: 'translateX(-100%)' }, to: { transform: 'translateX(0)' } },
      },
      animation: {
        'fade-up': 'fade-up 0.5s cubic-bezier(0.22, 1, 0.36, 1) both',
        'fade-in': 'fade-in 0.3s ease-out both',
        float: 'float 3.2s ease-in-out infinite',
        'pulse-ring': 'pulse-ring 1.8s cubic-bezier(0.22, 1, 0.36, 1) infinite',
        indeterminate: 'indeterminate 1.4s ease-in-out infinite',
        shake: 'shake 0.4s ease-in-out',
        'slide-in': 'slide-in 0.28s cubic-bezier(0.22, 1, 0.36, 1) both',
      },
    },
  },
  plugins: [],
};
