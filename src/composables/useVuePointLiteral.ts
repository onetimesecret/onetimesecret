import { ref, onMounted, readonly } from 'vue';
import type { AuthenticationSettings, Cust, Plan } from '@/types/onetime';
import type Stripe from 'stripe';

export const useWindowProps = () => {
  const apitoken = ref<string | undefined>(window.apitoken);
  const authenticated = ref(window.authenticated);
  const available_plans = ref<{ [key: string]: Plan } | undefined>(window.available_plans);
  const baseuri = ref(window.baseuri);
  const cust = ref<Cust>(window.cust);
  const custid = ref(window.custid);
  const customer_since = ref<string | undefined>(window.customer_since);
  const custom_domains_record_count = ref<number | undefined>(window.custom_domains_record_count);
  const custom_domains = ref<string[] | undefined>(window.custom_domains);
  const domains_enabled = ref(window.domains_enabled);
  const email = ref(window.email);
  const frontend_host = ref(window.frontend_host);
  const locale = ref(window.locale);
  const is_default_locale = ref(window.is_default_locale);
  const supported_locales = ref(window.supported_locales);
  const ot_version = ref(window.ot_version);
  const ruby_version = ref(window.ruby_version);
  const shrimp = ref(window.shrimp);
  const site_host = ref(window.site_host);
  const vue_component_name = ref<string | undefined>(window.vue_component_name);
  const stripe_customer = ref<Stripe.Customer | undefined>(window.stripe_customer);
  const stripe_subscriptions = ref<Stripe.Subscription[] | undefined>(window.stripe_subscriptions);
  const form_fields = ref<{ [key: string]: string } | undefined>(window.form_fields);
  const authentication = ref<AuthenticationSettings>(window.authentication);

  const deobfuscateEmails = () => {
    if (typeof window.deobfuscateEmails === 'function') {
      window.deobfuscateEmails();
    }
  };

  onMounted(() => {
    deobfuscateEmails();
  });

  return {
    apitoken: readonly(apitoken),
    authenticated: readonly(authenticated),
    available_plans: readonly(available_plans),
    baseuri: readonly(baseuri),
    cust: readonly(cust),
    custid: readonly(custid),
    customer_since: readonly(customer_since),
    custom_domains_record_count: readonly(custom_domains_record_count),
    custom_domains: readonly(custom_domains),
    domains_enabled: readonly(domains_enabled),
    email: readonly(email),
    frontend_host: readonly(frontend_host),
    locale: readonly(locale),
    is_default_locale: readonly(is_default_locale),
    supported_locales: readonly(supported_locales),
    ot_version: readonly(ot_version),
    ruby_version: readonly(ruby_version),
    shrimp: readonly(shrimp),
    site_host: readonly(site_host),
    vue_component_name: readonly(vue_component_name),
    stripe_customer: readonly(stripe_customer),
    stripe_subscriptions: readonly(stripe_subscriptions),
    form_fields: readonly(form_fields),
    authentication: readonly(authentication),
    deobfuscateEmails,
  };
};
