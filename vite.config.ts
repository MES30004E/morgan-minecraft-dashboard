import {defineConfig} from 'vite';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig({base:'/morgan-minecraft-dashboard/',plugins:[tailwindcss()],resolve:{alias:{'@':new URL('./src',import.meta.url).pathname}}});
