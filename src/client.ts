import { createClient } from '@supabase/supabase-js';
// Publishable routing key; RLS and authenticated RPCs enforce all authorization.
export const supabase=createClient('https://iyhtknyrecnythgyuvbq.supabase.co','sb_publishable_dDZlVEtEIrMsyrUbV1C5bA_CR1_Czpj',{
 auth:{flowType:'pkce',persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
});
export const callbackUrl=new URL('/morgan-minecraft-dashboard/',window.location.origin).href;
