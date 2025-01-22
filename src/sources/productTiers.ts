export interface PaymentFrequency {
  value: string;
  label: string;
  priceSuffix: string;
}

export interface ProductTier {
  id: string;
  name: string;
  href: string;
  cta: string;
  price: { [key: string]: string };
  description: string;
  features: string[];
  featured: boolean;
}

export const paymentFrequencies: Array<PaymentFrequency> = [
  { value: 'monthly', label: 'Monthly', priceSuffix: '/month' },
  { value: 'annually', label: 'Yearly', priceSuffix: '/year' },
];

export const productTiers: Array<ProductTier> = [
  {
    id: 'tier-identity',
    name: 'Identity Plus',
    href: '/plans/identity',
    cta: 'Start today',
    price: {
      monthly: '$35',
      annually: '$365',
    },
    //description: "Secure sharing that elevates your brand and simplifies communication.",
    //description: "Elevate your brand with secure sharing that simplifies communication.",
    //description: "Elevate your brand with secure, streamlined communication.",
    description: 'Secure your brand, build customer trust with links from your domain.',
    features: [
      'Unlimited custom domains',
      'Custom branding with your logo',
      'Branded homepage destination',
      'Privacy-first design',
      'Full API access',
      'Meets and exceeds compliance standards',
    ],
    featured: false,
  },
  {
    id: 'tier-dedicated',
    name: 'Global Elite',
    href: '/plans/dedicated',
    cta: 'Coming this fall',
    price: {
      monthly: '$245',
      annually: '$2545',
    },
    description: 'Dedicated infrastructure for data-compliance and deep integrations.',
    features: [
      'Private cloud environment',
      'Fully customizable',
      'Enterprise-grade security and compliance',
      'Data locality options (EU, US)',
      'Scheduled delivery within 2-4 business days',
    ],

    featured: true,
  },
];
