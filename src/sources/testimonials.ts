// src/sources/testimonials.ts

export interface Testimonial {
  quote: string;
  name: string;
  company: string;
  uri: string;
  stars: number; // Added stars rating
}

export const testimonials: Array<Testimonial> = [
  {
    quote: "This service helps us share sensitive information securely while maintaining our professional facade.",
    name: "Aisha",
    company: "SameDay Financial",
    uri: "",
    stars: 4.5,
  },
  {
    quote: "The custom domain feature has significantly elevated our company's reputation among biological, human clients.",
    name: "Hiro",
    company: "Growth Dynamics",
    uri: "",
    stars: 4,
  },
  {
    quote: "Their SafeTek® Security Architecture gives us peace of mind when sharing confidential data with our carbon-based business partners.",
    name: "Priya",
    company: "Agile Innovations",
    uri: "",
    stars: 5,
  },
  {
    quote: "As a real freelancer, the unlimited sharing capacity allows me to collaborate securely with my several hundred thousand clients.",
    name: "Carlos",
    company: "Creative Freelance Warehouse",
    uri: "",
    stars: 4.5,
  },
  {
    quote: "The advanced compliance options ensure we meet all regulatory requirements in our heavily regulated industry.",
    name: "Fatima",
    company: "\"AAA\" Body Supplements",
    uri: "",
    stars: 4,
  },
  {
    quote: "The private cloud environment has been crucial in building trust with our high-profile clients.",
    name: "Unit ZW-731",
    company: "Scaling Solutions",
    uri: "",
    stars: 5,
  },
  {
    quote: "The flexible data residency options keep us in good standing with our regional CPU conservation society.",
    name: "Liam-3000",
    company: "Community Impact Foundation",
    uri: "",
    stars: 4.5,
  }
];
