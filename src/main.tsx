import React, {useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import type {Session} from '@supabase/supabase-js';
import {supabase,callbackUrl} from './client';
import './style.css';
import {Fleet} from './Fleet';

function App(){
 const [session,setSession]=useState<Session|null>(null),[loading,setLoading]=useState(true);
 const [message,setMessage]=useState(''),[busy,setBusy]=useState(false),[mode,setMode]=useState('login');
 const [memberships,setMemberships]=useState<{server_id:string;state:string}[]>([]);
 const [profile,setProfile]=useState<{display_name:string;statistics_public:boolean}|null>(null);
 useEffect(()=>{
  let active=true;
  supabase.auth.getSession().then(({data,error})=>{if(active){setSession(data.session);setLoading(false);if(error)setMessage(error.message);}}).catch(()=>{if(active){setLoading(false);setMessage('Could not load your session. Refresh to retry.');}});
  const {data}=supabase.auth.onAuthStateChange((event,next)=>{setSession(next);if(event==='PASSWORD_RECOVERY')setMode('new-password');});
  return ()=>{active=false;data.subscription.unsubscribe();};
 },[]);
 async function loadAccount(){
  if(!session)return;
  const [membershipResult,profileResult]=await Promise.all([
   supabase.from('memberships').select('server_id,state').eq('user_id',session.user.id),
   supabase.from('profiles').select('display_name,statistics_public').eq('id',session.user.id).maybeSingle()
  ]);
  if(membershipResult.error||profileResult.error)throw new Error(membershipResult.error?.message||profileResult.error?.message);
  setMemberships(membershipResult.data||[]);setProfile(profileResult.data);
 }
 useEffect(()=>{loadAccount().catch(e=>setMessage(e.message));},[session?.user.id]);
 async function run(action:()=>Promise<void>){setBusy(true);setMessage('');try{await action();}catch(e){setMessage(e instanceof Error?e.message:'Request failed. Try again.');}finally{setBusy(false);}}
 async function submit(event:React.FormEvent<HTMLFormElement>){
  event.preventDefault();const form=new FormData(event.currentTarget),email=String(form.get('email')||''),password=String(form.get('password')||'');
  await run(async()=>{
   let error;
   if(mode==='register'){
    ({error}=await supabase.auth.signUp({email,password,options:{emailRedirectTo:callbackUrl}}));
    if(!error)setMessage('Check your email to verify your account before signing in.');
   }else if(mode==='reset'){
    ({error}=await supabase.auth.resetPasswordForEmail(email,{redirectTo:callbackUrl}));
    if(!error)setMessage('If your account is eligible, a reset email will arrive.');
   }else if(mode==='new-password'){
    ({error}=await supabase.auth.updateUser({password}));if(!error){setMode('login');setMessage('Password updated.');}
   }else ({error}=await supabase.auth.signInWithPassword({email,password}));
   if(error)throw error;
  });
 }
 async function saveProfile(event:React.FormEvent<HTMLFormElement>){
  event.preventDefault();if(!session)return;const form=new FormData(event.currentTarget);
  await run(async()=>{
   const value={display_name:String(form.get('display_name')),statistics_public:form.get('statistics_public')==='on'};
   const {error}=profile?await supabase.from('profiles').update(value).eq('id',session.user.id):await supabase.from('profiles').insert({id:session.user.id,display_name:value.display_name});
   if(error)throw error;await loadAccount();setMessage('Profile saved.');
  });
 }
 return <div className="shell"><aside><a className="brand" href={callbackUrl}><span className="mark">M</span><span>MORGAN<small>MINECRAFT CONTROL</small></span></a><div className="nav-label">YOUR COMMUNITY</div><a className="selected" href="#servers">◈ &nbsp; All servers</a><div className="aside-foot"><span className="dot"/> Multiple servers<br/><small>Built for your next adventure.</small></div></aside><div className="workspace"><header><span>Community / <strong>{session?'Your servers':'Welcome'}</strong></span><span className="badge">JAVA EDITION</span></header><main><div className="eyebrow">MORGAN'S WORLD</div><h1>{session?'Make yourself at home.':'Your world. Together.'}</h1><p className="intro">One place for your Minecraft community, player identity and server access.</p>
 {message&&<div role="status" className="notice">{message}</div>}
 {loading?<section aria-busy="true">Loading your account…</section>:!session||mode==='new-password'?<div className="auth-grid"><section><div className="section-kicker">WELCOME TO THE SERVER</div><h2>{mode==='register'?'Create your account':mode==='reset'?'Reset your password':mode==='new-password'?'Choose a new password':'Sign in to continue'}</h2><p>Connect with your community. Server access is approved by the owner after your Minecraft identity is verified.</p>{mode!=='new-password'&&<button className="google" disabled={busy} onClick={()=>run(async()=>{const {error}=await supabase.auth.signInWithOAuth({provider:'google',options:{redirectTo:callbackUrl,scopes:'openid email profile'}});if(error)throw error;})}>Continue with Google <span>↗</span></button>}
 <form onSubmit={submit}>{mode!=='new-password'&&<label>Email address<input name="email" type="email" autoComplete="email" required/></label>}{mode!=='reset'&&<label>Password<input name="password" type="password" autoComplete={mode==='login'?'current-password':'new-password'} minLength={mode==='login'?undefined:12} required/></label>}<button className="primary" disabled={busy}>{busy?'Working…':mode==='register'?'Create account':mode==='reset'?'Send reset email':mode==='new-password'?'Update password':'Sign in with email'}</button></form><div className="auth-links"><button disabled={busy} onClick={()=>setMode(mode==='register'?'login':'register')}>{mode==='register'?'Already have an account?':'Create an account'}</button><button disabled={busy} onClick={()=>setMode(mode==='reset'?'login':'reset')}>{mode==='reset'?'Back to sign in':'Forgot password?'}</button></div><p className="muted">Public email delivery is not configured yet. Use Google sign-in; email signup and resets may not deliver. Email verification remains required.</p></section><section className="world-info"><div className="section-kicker">THE COMMUNITY SERVER</div><h2>Something worth<br/>building together.</h2><dl><dt>Edition</dt><dd>Minecraft Java</dd><dt>Servers</dt><dd>Independent access and configuration</dd><dt>Connection</dt><dd>Public or private endpoints per server</dd></dl><p>Use your website account to manage access. Your Minecraft identity is verified separately in game.</p></section></div>:<><Fleet key={session.user.id} userId={session.user.id}/><div className="account-top"><span className="badge">SIGNED IN</span><button disabled={busy} onClick={()=>run(async()=>{const {error}=await supabase.auth.signOut();if(error)throw error;setProfile(null);setMemberships([]);})}>Sign out</button></div><div className="auth-grid"><section><h2>Your profile</h2><form onSubmit={saveProfile}><label>Display name<input name="display_name" required minLength={1} maxLength={64} defaultValue={profile?.display_name||''}/></label><label className="check"><input name="statistics_public" type="checkbox" defaultChecked={profile?.statistics_public||false} disabled={!profile}/>Share collected statistics with other members</label><button className="primary" disabled={busy}>Save profile</button></form><p className="muted">Website ID: <code>{session.user.id}</code></p></section><section><h2>Server access</h2>{memberships.length?memberships.map(m=><p key={m.server_id}>Membership: <strong>{m.state}</strong></p>):<p>Request membership above, then verify your Minecraft identity in the Linking tab.</p>}<p>Connection health and available server controls appear in the dashboard above.</p><p>Signing in does not prove ownership of a Minecraft username.</p><button disabled={busy} onClick={()=>run(loadAccount)}>Refresh account</button></section></div></>}
 <footer>Morgan Minecraft Community <span>Secure access · Shared adventures</span></footer></main></div></div>;
}
createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
