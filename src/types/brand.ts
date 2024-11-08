// These need to match UpdateDomainBrand#update_brand_settings valid_keys
export interface BrandSettings {
  primary_color: string;
  instructions_pre_reveal: string;
  instructions_reveal: string;
  instructions_post_reveal: string;
  button_text_light: boolean;
  font_family: string;
  corner_style: string;
  allow_public_homepage: boolean;
  allow_public_api: boolean;
}

// The javascript handoff dumps the booleans as strings.
export interface BrokenBrandSettings {
  primary_color: string;
  instructions_pre_reveal: string;
  instructions_reveal: string;
  instructions_post_reveal: string;
  button_text_light: string; // This is a string in the incoming data
  font_family: string;
  corner_style: string;
  allow_public_homepage: string;
  allow_public_api: string;
}
