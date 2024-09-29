import{d as C,u as M,r as k,G as K,o as n,c as i,b as e,e as t,p as S,J as D,i as v,I as P,t as a,g as b,f as $,y as A,K as N,F as V,L as U,j as I,k as T,n as j,M as q,N as B,O as L,P as z,a as E,m as G,h as H}from"./main-DAdj96k2.js";import{a as W}from"./useFetchData-CotLmwbY.js";import{u as F}from"./useFormSubmission-D8P3Furg.js";import{_ as J}from"./DashboardTabNav.vue_vue_type_script_setup_true_lang-CGkKTkDR.js";const O=["value"],Q=e("div",{class:"hidden"},[e("label",{for:"username"},"Username"),e("input",{type:"text",id:"username",autocomplete:"username"})],-1),R={class:"relative mb-4"},Y=e("label",{for:"currentPassword",id:"currentPasswordLabel",class:"dark:text-gray-300 block text-sm font-medium text-gray-700"},"Current Password",-1),X={class:"relative"},Z=["type"],ee={class:"relative mb-4"},te=e("label",{for:"newPassword",id:"newPasswordLabel",class:"dark:text-gray-300 block text-sm font-medium text-gray-700"},"New Password",-1),se={class:"relative"},oe=["type"],ae={class:"relative mb-4"},re=e("label",{for:"confirmPassword",id:"confirmPasswordlabel",class:"dark:text-gray-300 block text-sm font-medium text-gray-700"},"Confirm",-1),ne={class:"relative"},ie=["type"],ce={key:0,class:"mb-4 text-red-500"},le={key:1,class:"mb-4 text-green-500"},de={type:"submit",class:"hover:bg-gray-600 flex items-center justify-center w-full px-4 py-2 text-white bg-gray-500 rounded"},ue=e("i",{class:"fas fa-save mr-2"},null,-1),pe=C({__name:"AccountChangePasswordForm",props:{apitoken:{}},emits:["update:password"],setup(x,{emit:c}){const u=M(),m=k(""),l=k(""),s=k(""),r=K({current:!1,new:!1,confirm:!1}),_=c,{isSubmitting:o,error:h,success:g,submitForm:p}=F({url:"/api/v2/account/change-password",successMessage:"Password updated successfully.",onSuccess(){_("update:password")}}),f=w=>{r[w]=!r[w]};return(w,d)=>(n(),i("form",{onSubmit:d[6]||(d[6]=A((...y)=>t(p)&&t(p)(...y),["prevent"]))},[e("input",{type:"hidden",name:"shrimp",value:t(u).shrimp},null,8,O),Q,e("div",R,[Y,e("div",X,[S(e("input",{type:r.current?"text":"password",name:"currentp",id:"currentPassword","onUpdate:modelValue":d[0]||(d[0]=y=>m.value=y),required:"",tabindex:"1",autocomplete:"current-password","aria-label":"Current Password","aria-labelledby":"currentPasswordLabel",class:"dark:border-gray-600 focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white block w-full pr-10 mt-1 border-gray-300 rounded-md shadow-sm"},null,8,Z),[[D,m.value]]),e("button",{type:"button",onClick:d[1]||(d[1]=y=>f("current")),class:"absolute inset-y-0 right-0 flex items-center pr-3"},[v(t(P),{icon:r.current?"heroicons-solid:eye":"heroicons-outline:eye-off",class:"dark:text-gray-100 w-5 h-5 text-gray-400","aria-hidden":"true"},null,8,["icon"])])])]),e("div",ee,[te,e("div",se,[S(e("input",{type:r.new?"text":"password",name:"newp",id:"newPassword","onUpdate:modelValue":d[2]||(d[2]=y=>l.value=y),required:"",tabindex:"2",autocomplete:"new-password","aria-label":"New Password","aria-labelledby":"newPasswordLabel",class:"dark:border-gray-600 focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white block w-full pr-10 mt-1 border-gray-300 rounded-md shadow-sm"},null,8,oe),[[D,l.value]]),e("button",{type:"button",onClick:d[3]||(d[3]=y=>f("new")),class:"hover:text-gray-600 dark:text-gray-300 dark:hover:text-gray-100 absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400"},[v(t(P),{icon:r.new?"heroicons-solid:eye":"heroicons-outline:eye-off",class:"dark:text-gray-100 w-5 h-5 text-gray-400","aria-hidden":"true"},null,8,["icon"])])])]),e("div",ae,[re,e("div",ne,[S(e("input",{type:r.confirm?"text":"password",name:"newp2",id:"confirmPassword","onUpdate:modelValue":d[4]||(d[4]=y=>s.value=y),required:"",tabindex:"3",autocomplete:"confirm-password","aria-label":"New Password","aria-labelledby":"confirmPasswordlabel",class:"dark:border-gray-600 focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white block w-full pr-10 mt-1 border-gray-300 rounded-md shadow-sm"},null,8,ie),[[D,s.value]]),e("button",{type:"button",onClick:d[5]||(d[5]=y=>f("confirm")),class:"absolute inset-y-0 right-0 flex items-center pr-3"},[v(t(P),{icon:r.confirm?"heroicons-solid:eye":"heroicons-outline:eye-off",class:"dark:text-gray-100 w-5 h-5 text-gray-400","aria-hidden":"true"},null,8,["icon"])])])]),t(h)?(n(),i("div",ce,a(t(h)),1)):b("",!0),t(g)?(n(),i("div",le,a(t(g)),1)):b("",!0),e("button",de,[ue,$(" "+a(t(o)?"Updating...":"Update Password"),1)])],32))}}),me=U('<p class="dark:text-gray-300 mb-4">Please be advised:</p><ul class="dark:text-gray-300 mb-4 list-disc list-inside"><li><span class="font-bold">Secrets will remain active until they expire.</span></li><li>Any secrets you wish to remove, <span class="underline">burn them before continuing</span>.</li><li>Deleting your account is <span class="italic">permanent and non-reversible.</span></li></ul>',2),ge=e("i",{class:"fas fa-trash-alt mr-2"},null,-1),_e={class:"dark:text-gray-400 mt-2 text-sm text-gray-500"},he={key:0,class:"fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50"},ye=["value"],be={class:"dark:bg-gray-800 p-6 bg-white rounded-lg shadow-lg"},fe=e("h3",{class:"dark:text-white mb-4 text-xl font-bold text-gray-900"},"Confirm Account Deletion",-1),xe=e("p",{class:"dark:text-gray-300 mb-4 text-gray-700"},"Are you sure you want to permanently delete your account? This action cannot be undone.",-1),we=e("input",{type:"hidden",name:"tabindex",value:"destroy"},null,-1),ve={class:"mb-4"},ke={key:0,class:"mb-4 text-red-500"},$e={key:1,class:"mb-4 text-green-500"},Pe={class:"flex justify-end space-x-4"},Ce=["disabled"],Se={key:0,class:"animate-spin w-5 h-5 mr-3 -ml-1 text-white",xmlns:"http://www.w3.org/2000/svg",fill:"none",viewBox:"0 0 24 24"},Ae=e("circle",{class:"opacity-25",cx:"12",cy:"12",r:"10",stroke:"currentColor","stroke-width":"4"},null,-1),De=e("path",{class:"opacity-75",fill:"currentColor",d:"M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"},null,-1),Me=[Ae,De],Fe={key:1,xmlns:"http://www.w3.org/2000/svg",class:"w-5 h-5 mr-2",width:"20",height:"20",viewBox:"0 0 20 20",fill:"currentColor"},Ie=e("path",{"fill-rule":"evenodd",d:"M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z","clip-rule":"evenodd"},null,-1),Ve=[Ie],Ke=C({__name:"AccountDeleteButtonWithModalForm",props:{apitoken:{},cust:{}},emits:["delete:account"],setup(x,{emit:c}){const u=M(),m=c,l=k(!1),s=k(""),{isSubmitting:r,error:_,success:o,submitForm:h}=F({url:"/api/v2/account/destroy",successMessage:"Account deleted successfully.",onSuccess:()=>{m("delete:account"),l.value=!1,window.location.href="/"}}),g=()=>{l.value=!0},p=()=>{l.value=!1,s.value=""};return(f,w)=>{var d;return n(),i(V,null,[me,e("button",{onClick:g,class:"hover:bg-red-700 flex items-center justify-center w-full px-4 py-2 font-bold text-white bg-red-600 rounded"},[ge,$(" Permanently Delete Account ")]),e("p",_e,"Deleting "+a((d=f.cust)==null?void 0:d.custid),1),l.value?(n(),i("div",he,[e("form",{onSubmit:w[1]||(w[1]=A((...y)=>t(h)&&t(h)(...y),["prevent"])),class:"w-full max-w-md"},[e("input",{type:"hidden",name:"shrimp",value:t(u).shrimp},null,8,ye),e("div",be,[fe,xe,we,e("div",ve,[S(e("input",{"onUpdate:modelValue":w[0]||(w[0]=y=>s.value=y),name:"confirmation",type:"password",class:"focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white w-full px-3 py-2 border border-gray-300 rounded-md",autocomplete:"confirmation",placeholder:"Confirm with your password"},null,512),[[N,s.value]])]),t(_)?(n(),i("p",ke,a(t(_)),1)):b("",!0),t(o)?(n(),i("p",$e,a(t(o)),1)):b("",!0),e("div",Pe,[e("button",{onClick:p,type:"button",class:"hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-gray-400 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600 px-4 py-2 text-gray-800 bg-gray-200 rounded-md"}," Cancel "),e("button",{type:"submit",disabled:!s.value||t(r),class:"hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 dark:bg-red-700 dark:hover:bg-red-800 disabled:opacity-50 disabled:cursor-not-allowed flex items-center px-4 py-2 text-white bg-red-600 rounded-md"},[t(r)?(n(),i("svg",Se,Me)):(n(),i("svg",Fe,Ve)),$(" "+a(t(r)?"Deleting...":"Delete Account"),1)],8,Ce)])])],32)])):b("",!0)],64)}}}),Ne={key:0,class:"bg-white dark:bg-gray-800 p-6 rounded-lg shadow-md space-y-6 mb-6"},Ue={class:"flex items-center justify-between"},Te={class:"text-2xl font-bold text-gray-900 dark:text-white flex items-center"},je=e("a",{href:"/account/billing_portal",class:"inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-brandcomp-500 hover:bg-brandcomp-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brandcomp-500 transition-colors duration-150"}," Manage Subscription ",-1),qe={class:"grid grid-cols-1 md:grid-cols-2 gap-6"},Be={class:"space-y-4"},Le=e("h3",{class:"text-lg font-semibold text-gray-700 dark:text-gray-300"},"Customer Information",-1),ze={class:"text-sm text-gray-600 dark:text-gray-400 space-y-2"},Ee={key:0},Ge={key:1},He={key:0,class:"space-y-4"},We=e("h3",{class:"text-lg font-semibold text-gray-700 dark:text-gray-300"},"Default Payment Method",-1),Je={class:"flex items-center text-sm text-gray-600 dark:text-gray-400"},Oe={class:"space-y-6"},Qe=e("h3",{class:"text-lg font-semibold text-gray-700 dark:text-gray-300"},"Subscriptions",-1),Re={class:"flex justify-between items-center mb-4"},Ye={class:"text-sm font-medium text-gray-700 dark:text-gray-300"},Xe={class:"text-sm text-gray-600 dark:text-gray-400"},Ze={key:0},et=C({__name:"AccountBillingSection",props:{stripeCustomer:{default:null},stripeSubscriptions:{default:()=>[]}},setup(x){const c=x,u=s=>new Date(s*1e3).toLocaleDateString(),m=I(()=>{var s,r;return(r=(s=c.stripeCustomer)==null?void 0:s.invoice_settings)==null?void 0:r.default_payment_method}),l=I(()=>c.stripeSubscriptions.map(s=>{var r,_,o,h,g,p;return{id:s.id,status:s.status,amount:((_=(r=s.items.data[0])==null?void 0:r.price)==null?void 0:_.unit_amount)??0,quantity:((o=s.items.data[0])==null?void 0:o.quantity)??1,interval:((p=(g=(h=s.items.data[0])==null?void 0:h.price)==null?void 0:g.recurring)==null?void 0:p.interval)??"month",currentPeriodEnd:s.current_period_end}}));return(s,r)=>{var _;return c.stripeSubscriptions.length>0&&c.stripeCustomer?(n(),i("div",Ne,[e("header",Ue,[e("h2",Te,[v(t(P),{icon:"mdi:credit-card-outline",class:"w-6 h-6 mr-2 text-brandcomp-500"}),$(" Subscription ")]),je]),e("section",qe,[e("div",Be,[Le,e("ul",ze,[e("li",null,"Customer since: "+a(u(c.stripeCustomer.created)),1),c.stripeCustomer.email?(n(),i("li",Ee,"Email: "+a(c.stripeCustomer.email),1)):b("",!0),c.stripeCustomer.balance!==0?(n(),i("li",Ge," Account balance: $"+a((c.stripeCustomer.balance/100).toFixed(2)),1)):b("",!0)])]),(_=m.value)!=null&&_.card?(n(),i("div",He,[We,e("div",Je,[v(t(P),{icon:"mdi:credit-card",class:"w-8 h-8 mr-2 text-gray-400"}),$(" "+a(m.value.card.brand)+" ending in "+a(m.value.card.last4),1)])])):b("",!0)]),e("section",Oe,[Qe,(n(!0),i(V,null,T(l.value,o=>(n(),i("div",{key:o.id,class:"bg-gray-50 dark:bg-gray-700 p-4 rounded-lg"},[e("div",Re,[e("span",{class:j(["px-2 py-1 text-xs font-semibold rounded-full",o.status==="active"?"bg-green-100 text-green-800 dark:bg-green-800 dark:text-green-100":"bg-yellow-100 text-yellow-800 dark:bg-yellow-800 dark:text-yellow-100"])},a(o.status.charAt(0).toUpperCase()+o.status.slice(1)),3),e("span",Ye," $"+a((o.amount*o.quantity/100).toFixed(2))+" / "+a(o.interval),1)]),e("div",Xe,[o.quantity>1?(n(),i("p",Ze," Quantity: "+a(o.quantity)+" x $"+a((o.amount/100).toFixed(2)),1)):b("",!0),e("p",null,"Next billing date: "+a(u(o.currentPeriodEnd)),1)])]))),128))])])):b("",!0)}}}),tt=x=>(q("data-v-9e123fa9"),x=x(),B(),x),st={key:0,class:"mb-4 p-4 bg-gradient-to-r from-pink-500 via-red-500 to-yellow-400 rounded-lg shadow-lg"},ot={class:"font-mono text-lg text-white"},at={class:"bg-black bg-opacity-20 p-3 rounded flex items-center overflow-x-auto relative"},rt={class:"break-all pr-10"},nt=tt(()=>e("p",{class:"text-white text-sm mt-2 font-semibold"}," 🔐 Keep this token secure! It provides full access to your account. ",-1)),it=C({__name:"APIKeyCard",props:{apitoken:{default:""},onCopy:{type:Function,default:()=>{}}},setup(x){const c=x,u=k(!1),m=()=>{navigator.clipboard.writeText(c.apitoken).then(()=>{u.value=!0,setTimeout(()=>{u.value=!1},2e3),c.onCopy()}).catch(l=>{console.error("Failed to copy text: ",l)})};return(l,s)=>l.apitoken?(n(),i("div",st,[e("div",ot,[e("div",at,[e("span",rt,a(l.apitoken),1),e("button",{onClick:A(m,["stop"]),type:"button",class:"absolute right-2 top-1/2 transform -translate-y-1/2 text-white hover:text-gray-200 transition-colors duration-200"},[v(t(P),{icon:u.value?"heroicons-outline:check":"heroicons-outline:clipboard-copy",class:"w-6 h-6"},null,8,["icon"])])])]),nt])):b("",!0)}}),ct=L(it,[["__scopeId","data-v-9e123fa9"]]),lt=["value"],dt={key:0,class:"mb-4 text-red-500"},ut={key:1,class:"mb-4 text-green-500"},pt={type:"submit",class:"hover:bg-gray-600 flex items-center justify-center w-full px-4 py-2 text-white bg-gray-500 rounded"},mt=e("i",{class:"fas fa-trash-alt mr-2"},null,-1),gt=e("p",{class:"dark:text-gray-400 mt-2 text-sm text-gray-500"},null,-1),_t=C({__name:"APIKeyForm",props:{apitoken:{}},emits:["update:apitoken"],setup(x,{emit:c}){const u=M(),m=x,l=c,s=k(m.apitoken);z(()=>m.apitoken,g=>{s.value=g});const{isSubmitting:r,error:_,success:o,submitForm:h}=F({url:"/api/v2/account/apitoken",successMessage:"Token generated.",onSuccess:async g=>{var f;const p=((f=g.record)==null?void 0:f.apitoken)||"";s.value=p,l("update:apitoken",p)}});return(g,p)=>(n(),i("form",{onSubmit:p[0]||(p[0]=A((...f)=>t(h)&&t(h)(...f),["prevent"]))},[e("input",{type:"hidden",name:"shrimp",value:t(u).shrimp},null,8,lt),v(ct,{apitoken:s.value},null,8,["apitoken"]),t(_)?(n(),i("div",dt,a(t(_)),1)):b("",!0),t(o)?(n(),i("div",ut,a(t(o)),1)):b("",!0),e("button",pt,[mt,$(" "+a(t(r)?"Generating...":"Generate Token"),1)]),gt],32))}}),ht={class:""},yt=e("h1",{class:"dark:text-white mb-6 text-3xl font-bold"},"Your Account",-1),bt={class:"dark:text-gray-300 mb-4 text-lg"},ft={class:"dark:bg-gray-800 p-6 mb-6 bg-white rounded-lg shadow"},xt=e("h2",{class:"dark:text-white flex items-center mb-4 text-xl font-semibold"},[e("i",{class:"fas fa-exclamation-triangle mr-2 text-red-500"}),e("span",{class:"flex-1"},"API Key")],-1),wt={class:"pl-3"},vt={class:"dark:bg-gray-800 p-6 mb-6 bg-white rounded-lg shadow"},kt=e("h2",{class:"dark:text-white flex items-center mb-4 text-xl font-semibold"},[e("i",{class:"fas fa-lock mr-2"}),$(" Update Password ")],-1),$t={class:"pl-3"},Pt={class:"dark:bg-gray-800 p-6 bg-white rounded-lg shadow"},Ct=e("h2",{class:"dark:text-white flex items-center mb-4 text-xl font-semibold"},[e("i",{class:"fas fa-exclamation-triangle mr-2 text-red-500"}),e("span",{class:"flex-1"},"Delete Account")],-1),St={class:"pl-3"},At={class:"dark:text-gray-400 mt-6 text-sm text-gray-600"},Vt=C({__name:"AccountIndex",setup(x){const{plan:c,cust:u,customer_since:m}=E(["plan","cust","customer_since"]),{record:l,fetchData:s}=W({url:"/api/v2/account",onSuccess:r=>{r[0]}});return G(s),(r,_)=>{var o,h,g,p,f,w;return n(),i("div",ht,[v(J),yt,e("p",bt,"Account type: "+a((h=(o=t(c))==null?void 0:o.options)==null?void 0:h.name),1),e("div",ft,[xt,e("div",wt,[v(_t,{apitoken:(g=t(l))==null?void 0:g.apitoken},null,8,["apitoken"])])]),v(et,{"stripe-customer":(p=t(l))==null?void 0:p.stripe_customer,"stripe-subscriptions":(f=t(l))==null?void 0:f.stripe_subscriptions},null,8,["stripe-customer","stripe-subscriptions"]),e("div",vt,[kt,e("div",$t,[v(pe)])]),e("div",Pt,[Ct,e("div",St,[t(u)?(n(),H(Ke,{key:0,cust:t(u)},null,8,["cust"])):b("",!0)])]),e("p",At," Created "+a((w=t(u))==null?void 0:w.secrets_created)+" secrets since "+a(t(m))+". ",1)])}}});export{Vt as default};
