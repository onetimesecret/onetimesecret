import { type PlanFeature, isPlanFeature } from '@/schemas/contracts/authorization-registry';
import { toValue, type MaybeRefOrGetter } from 'vue';

type FeatureSource = {
  plan_entitlements?: readonly string[];
  entitlements?: readonly string[] | null;
};

/** Standalone and billed servers both report their effective organization features. */
export function useFeatures(organization: MaybeRefOrGetter<FeatureSource | null | undefined>) {
  const hasFeature = (feature: PlanFeature): boolean => {
    const org = toValue(organization);
    const features = org?.plan_entitlements ?? org?.entitlements;
    return isPlanFeature(feature) && features?.includes(feature) === true;
  };
  return { hasFeature };
}
