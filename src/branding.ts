/** Public build-time display name only. Never place credentials in VITE_* values. */
export function displayName(value:unknown):string {
 if(typeof value!=='string')return 'Minecraft Console';
 const name=value.trim();
 return name.length>0&&name.length<=80&&!/[\u0000-\u001f\u007f]/.test(name)?name:'Minecraft Console';
}
export const APP_NAME=displayName(import.meta.env?.VITE_APP_DISPLAY_NAME);
