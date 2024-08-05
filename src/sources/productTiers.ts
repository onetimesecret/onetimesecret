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
    href: '/plans/tier-identity',
    cta: 'Choose this plan',
    price: {
      monthly: '$35',
      annually: '$365',
    },
    description: "Secure sharing that elevates your brand and simplifies communication.",
    //description: "Elevate your brand with secure sharing that simplifies communication.",
    //description: "Elevate your brand with secure, streamlined communication.",
    features: [
      'Branded custom domain',
      'Unlimited sharing capacity',
      'Enhanced privacy features',
      'Full API access',
    ],
    featured: false,
  },
  {
    id: 'tier-dedication',
    name: 'Global Elite',
    href: '#',
    cta: 'Coming Soon',
    price: {
      monthly: '$000',
      annually: '$1111'
    },
    description: 'Dedicated infrastructure with data-compliance controls and unlimited scalability.',
    //description: 'Enterprise-grade infrastructure for data-compliance and deep integrations.',
    features: [
      'Private cloud environment',
      'Unlimited usage and scaling',
      'Advanced identity management',
      'Multiple data location choices (EU, US)',
      'Full regulatory compliance (including GDPR, CCPA, HIPAA)',
    ],

    featured: true,
  },
]
