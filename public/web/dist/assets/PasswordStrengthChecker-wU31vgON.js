import{d as p,r as a,i as h,j as _,c,n as k,e as x,b as w,t as P,h as m,o as d}from"./main-BSXUZJnf.js";const b={class:"font-bold"},y={key:1,class:"mb-4 text-red-500 dark:text-red-400"},E=p({__name:"PasswordStrengthChecker",setup(B){const s=a(""),l=a(""),n=a(0),u=a(!1),r=a(!1),v=h(()=>({0:"Not great",1:"Meh",2:"Fair",3:"Pretty good",4:"Great"})[n.value]),g=h(()=>n.value>2?"text-green-500 dark:text-green-400":"text-red-500 dark:text-red-400"),f=e=>{let t=0;e.match(/[a-z]/)&&e.match(/[A-Z]/)&&t++,e.match(/\d/)&&t++,e.match(/[^a-zA-Z\d]/)&&t++,e.length>=6&&t++,e.length<=6&&(t=0),n.value=t},i=()=>{u.value=s.value!==l.value};return _(()=>{const e=document.getElementById("passField"),t=document.getElementById("pass2Field");e&&t&&(e.addEventListener("input",o=>{s.value=o.target.value,f(s.value),r.value&&i()}),t.addEventListener("input",o=>{l.value=o.target.value,r.value=!0,i()}))}),(e,t)=>(d(),c("div",null,[s.value?(d(),c("div",{key:0,class:k([g.value,"mb-4"])},[x(" Password Strength: "),w("span",b,P(v.value),1)],2)):m("",!0),r.value&&u.value?(d(),c("div",y," Passwords do not match ")):m("",!0)]))}});export{E as default};
