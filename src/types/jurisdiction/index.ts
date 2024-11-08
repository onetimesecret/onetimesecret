
// Jurisdiction class extending BaseEntity
export class Jurisdiction extends BaseEntity {
  // Additional properties specific to Jurisdiction can be added here
}

// Region class extending BaseEntity
export class Region extends BaseEntity {
  // Additional properties specific to Region can be added here
}

// Note: "Regions" is not a list of Region objects. It represents the site settings for all regions. A better name would be RegionsConfig.
export interface Regions {
  enabled: boolean;
  current_jurisdiction: string;
  jurisdictions: Jurisdiction[];
}
