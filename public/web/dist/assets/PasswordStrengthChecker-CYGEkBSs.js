import{d as p,r as a,l as u,m as _,o as i,c as h,a as m,h as x,t as k,n as w,e as P}from"./main-oYL6ejTX.js";const b={class:"font-bold"},y={key:0,class:"mb-4 text-red-500 dark:text-red-400"},E=p({__name:"PasswordStrengthChecker",setup(B){const s=a(""),c=a(""),n=a(0),d=a(!1),r=a(!1),v=u(()=>({0:"Not great",1:"Meh",2:"Fair",3:"Pretty good",4:"Great"})[n.value]),g=u(()=>n.value>2?"text-green-500 dark:text-green-400":"text-red-500 dark:text-red-400"),f=e=>{let t=0;e.match(/[a-z]/)&&e.match(/[A-Z]/)&&t++,e.match(/\d/)&&t++,e.match(/[^a-zA-Z\d]/)&&t++,e.length>=6&&t++,e.length<=6&&(t=0),n.value=t},l=()=>{d.value=s.value!==c.value};return _(()=>{const e=document.getElementById("passField"),t=document.getElementById("pass2Field");e&&t&&(e.addEventListener("input",o=>{s.value=o.target.value,f(s.value),r.value&&l()}),t.addEventListener("input",o=>{c.value=o.target.value,r.value=!0,l()}))}),(e,t)=>(i(),h("div",null,[m("div",{class:w([g.value,"mb-4"])},[x(" Password Strength: "),m("span",b,k(v.value),1)],2),r.value&&d.value?(i(),h("div",y," Passwords do not match ")):P("",!0)]))}});export{E as default};
