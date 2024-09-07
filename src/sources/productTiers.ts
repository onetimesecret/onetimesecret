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
]

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
    description: "Secure your brand, build customer trust with links from your domain.",
    features: [
      'Unlimited custom domains',
      //'Unlimited sharing capacity',
      'Privacy-first design',
      'Full API access',
      'Meets and exceeds compliance standards',
    ],
    featured: false,
  },
  {
    id: 'tier-dedication',
    name: 'Global Elite',
    href: '/plans/dedication',
    cta: 'Coming this fall',
    price: {
      monthly: '$111',
      annually: '$000'
    },
    description: 'Dedicated infrastructure with data-compliance controls and SLAs.',
    //description: 'Enterprise-grade infrastructure for data-compliance and deep integrations.',
    features: [
      'Private cloud environment',
      'Unlimited usage and scaling',
      'Advanced team management',
      'Multiple data locations (EU, US, AU)',
      'Service level agreements',
    ],

    featured: true,
  },
]
