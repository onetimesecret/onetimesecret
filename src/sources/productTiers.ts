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

export const productTiers: Array<ProductTier> = [
  {
    id: 'tier-identity',
    name: 'Identity Plus',
    href: '/plans/tier-identity',
    cta: 'Choose this plan',
    price: {
      monthly: '$34',
      annually: '$365'
    },
    //description: "Elevate your brand with secure sharing that simplifies communication.",
    description: "Secure sharing that elevates your brand and simplifies communication.",
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
    href: '/plans/tier-dedication',
    cta: 'Coming Soon',
    price: {
      monthly: '$L0W',
      annually: '$H1GH'
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
