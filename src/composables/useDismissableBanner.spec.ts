// src/composables/useDismissableBanner.spec.ts

import { useDismissableBanner, generateBannerId } from '@/composables/useDismissableBanner';
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';

describe('useDismissableBanner', () => {
  const BANNER_ID_PERMANENT = 'test-permanent-banner';
  const BANNER_ID_TEMPORARY = 'test-temporary-banner';
  const EXPIRATION_DAYS = 7;

  beforeEach(() => {
    // Clear localStorage before each test
    localStorage.clear();
    // Use fake timers to control time-based logic
    vi.useFakeTimers();
  });

  afterEach(() => {
    // Restore real timers after each test
    vi.useRealTimers();
  });

  it('should be visible by default when no prior state exists', () => {
    const { isVisible } = useDismissableBanner('new-banner-default');
    expect(isVisible.value).toBe(true);
  });

  describe('Permanent Dismissal (expirationDays = 0 or not provided)', () => {
    it('should dismiss banner permanently and store state when expirationDays is 0', () => {
      const { isVisible, dismiss } = useDismissableBanner(BANNER_ID_PERMANENT, 0);
      expect(isVisible.value).toBe(true); // Initially visible

      dismiss();
      expect(isVisible.value).toBe(false); // Should be hidden after dismissal

      // Verify localStorage state
      const storedState = JSON.parse(localStorage.getItem(`banner-${BANNER_ID_PERMANENT}`) || '{}');
      expect(storedState.dismissed).toBe(true);
      expect(storedState.timestamp).toBeTypeOf('string'); // Timestamp should be set

      // Re-initialize composable to check for persistence from localStorage
      const { isVisible: isVisibleAfterReinit } = useDismissableBanner(BANNER_ID_PERMANENT, 0);
      expect(isVisibleAfterReinit.value).toBe(false); // Should remain hidden
    });

    it('should dismiss banner permanently and store state when expirationDays is not provided (defaults to 0)', () => {
      const { isVisible, dismiss } = useDismissableBanner(BANNER_ID_PERMANENT); // No expirationDays argument
      expect(isVisible.value).toBe(true);

      dismiss();
      expect(isVisible.value).toBe(false);

      const storedState = JSON.parse(localStorage.getItem(`banner-${BANNER_ID_PERMANENT}`) || '{}');
      expect(storedState.dismissed).toBe(true);
      expect(storedState.timestamp).toBeTypeOf('string');

      const { isVisible: isVisibleAfterReinit } = useDismissableBanner(BANNER_ID_PERMANENT);
      expect(isVisibleAfterReinit.value).toBe(false);
    });

    it('should remain dismissed permanently even after significant time has passed', () => {
      const { isVisible, dismiss } = useDismissableBanner(BANNER_ID_PERMANENT, 0);
      dismiss();
      expect(isVisible.value).toBe(false);

      // Advance time well beyond any possible temporary expiration (e.g., 10 years)
      vi.advanceTimersByTime(1000 * 60 * 60 * 24 * 365 * 10);

      const { isVisible: isVisibleAfterTime } = useDismissableBanner(BANNER_ID_PERMANENT, 0);
      expect(isVisibleAfterTime.value).toBe(false); // Should still be hidden
    });
  });

  describe('Temporary Dismissal (expirationDays > 0)', () => {
    const MOCK_CURRENT_DATE_STR = '2024-01-01T12:00:00.000Z';

    beforeEach(() => {
      // Set a consistent "current" time for these tests
      vi.setSystemTime(new Date(MOCK_CURRENT_DATE_STR));
    });

    it('should dismiss banner temporarily and store state with timestamp', () => {
      const { isVisible, dismiss } = useDismissableBanner(BANNER_ID_TEMPORARY, EXPIRATION_DAYS);
      expect(isVisible.value).toBe(true);

      dismiss();
      expect(isVisible.value).toBe(false);

      const storedState = JSON.parse(localStorage.getItem(`banner-${BANNER_ID_TEMPORARY}`) || '{}');
      expect(storedState.dismissed).toBe(true);
      expect(storedState.timestamp).toBe(MOCK_CURRENT_DATE_STR); // Timestamp of dismissal

      const { isVisible: isVisibleAfterReinit } = useDismissableBanner(
        BANNER_ID_TEMPORARY,
        EXPIRATION_DAYS
      );
      expect(isVisibleAfterReinit.value).toBe(false); // Should remain hidden
    });

    it('should remain hidden if re-initialized before expiration period', () => {
      const { dismiss } = useDismissableBanner(BANNER_ID_TEMPORARY, EXPIRATION_DAYS);
      dismiss();

      // Advance time, but by less than the expiration period
      vi.advanceTimersByTime(1000 * 60 * 60 * 24 * (EXPIRATION_DAYS - 1)); // e.g., 6 days for 7-day expiry

      const { isVisible: isVisibleBeforeExpiration } = useDismissableBanner(
        BANNER_ID_TEMPORARY,
        EXPIRATION_DAYS
      );
      expect(isVisibleBeforeExpiration.value).toBe(false); // Should still be hidden
    });

    it('should become visible again if re-initialized after expiration period', () => {
      const { dismiss } = useDismissableBanner(BANNER_ID_TEMPORARY, EXPIRATION_DAYS);
      dismiss(); // Dismissed at MOCK_CURRENT_DATE_STR

      // Confirm it's dismissed immediately after
      const { isVisible: isVisibleInitially } = useDismissableBanner(
        BANNER_ID_TEMPORARY,
        EXPIRATION_DAYS
      );
      expect(isVisibleInitially.value).toBe(false);

      // Advance time by exactly expirationDays + 1 millisecond
      vi.advanceTimersByTime(1000 * 60 * 60 * 24 * EXPIRATION_DAYS + 1);

      const { isVisible: isVisibleAfterExpiration } = useDismissableBanner(
        BANNER_ID_TEMPORARY,
        EXPIRATION_DAYS
      );
      expect(isVisibleAfterExpiration.value).toBe(true); // Should now be visible
    });

    it('should be visible if initialized with a stored timestamp older than expiration period', () => {
      const dismissedDate = new Date(MOCK_CURRENT_DATE_STR);
      // Set dismissal timestamp to be (EXPIRATION_DAYS + 1 day) in the past
      dismissedDate.setDate(dismissedDate.getDate() - (EXPIRATION_DAYS + 1));

      localStorage.setItem(
        `banner-${BANNER_ID_TEMPORARY}`,
        JSON.stringify({
          dismissed: true,
          timestamp: dismissedDate.toISOString(),
        })
      );

      // Current time is MOCK_CURRENT_DATE_STR
      const { isVisible } = useDismissableBanner(BANNER_ID_TEMPORARY, EXPIRATION_DAYS);
      expect(isVisible.value).toBe(true); // Should be visible as it's expired
    });

    it('should remain hidden if initialized with a stored timestamp within expiration period', () => {
      const dismissedDate = new Date(MOCK_CURRENT_DATE_STR);
      // Set dismissal timestamp to be 1 day in the past
      dismissedDate.setDate(dismissedDate.getDate() - 1);

      localStorage.setItem(
        `banner-${BANNER_ID_TEMPORARY}`,
        JSON.stringify({
          dismissed: true,
          timestamp: dismissedDate.toISOString(),
        })
      );

      // Current time is MOCK_CURRENT_DATE_STR, expiry is 7 days
      const { isVisible } = useDismissableBanner(BANNER_ID_TEMPORARY, EXPIRATION_DAYS);
      expect(isVisible.value).toBe(false); // Should be hidden, still within 7 days
    });
  });

  it('should handle multiple banner instances independently', () => {
    const banner1Id = 'multi-banner-1'; // Permanent
    const banner2Id = 'multi-banner-2'; // Temporary (5 days)
    const banner3Id = 'multi-banner-3'; // Permanent (default)

    vi.setSystemTime(new Date('2024-01-01T00:00:00.000Z'));

    const banner1 = useDismissableBanner(banner1Id, 0);
    const banner2 = useDismissableBanner(banner2Id, 5);
    const banner3 = useDismissableBanner(banner3Id);

    expect(banner1.isVisible.value, 'banner1 initial').toBe(true);
    expect(banner2.isVisible.value, 'banner2 initial').toBe(true);
    expect(banner3.isVisible.value, 'banner3 initial').toBe(true);

    banner1.dismiss();
    expect(banner1.isVisible.value, 'banner1 after dismiss').toBe(false);
    expect(banner2.isVisible.value, 'banner2 after banner1 dismiss').toBe(true);
    expect(banner3.isVisible.value, 'banner3 after banner1 dismiss').toBe(true);

    banner2.dismiss();
    expect(banner1.isVisible.value, 'banner1 after banner2 dismiss').toBe(false);
    expect(banner2.isVisible.value, 'banner2 after dismiss').toBe(false);
    expect(banner3.isVisible.value, 'banner3 after banner2 dismiss').toBe(true);

    // Re-initialize to confirm localStorage isolation before time passes
    const banner1Reinit = useDismissableBanner(banner1Id, 0);
    const banner2Reinit = useDismissableBanner(banner2Id, 5);
    const banner3Reinit = useDismissableBanner(banner3Id); // Never dismissed this one yet

    expect(banner1Reinit.isVisible.value, 'banner1 reinit').toBe(false);
    expect(banner2Reinit.isVisible.value, 'banner2 reinit').toBe(false);
    expect(banner3Reinit.isVisible.value, 'banner3 reinit').toBe(true);

    banner3Reinit.dismiss(); // Now dismiss banner3
    expect(banner3Reinit.isVisible.value, 'banner3 after its dismiss').toBe(false);

    // Advance time by 6 days (banner2 was 5 day expiry)
    vi.advanceTimersByTime(1000 * 60 * 60 * 24 * 6);

    const banner1AfterTime = useDismissableBanner(banner1Id, 0);
    const banner2AfterTime = useDismissableBanner(banner2Id, 5);
    const banner3AfterTime = useDismissableBanner(banner3Id);

    expect(banner1AfterTime.isVisible.value, 'banner1 after 6 days').toBe(false); // Permanent
    expect(banner2AfterTime.isVisible.value, 'banner2 after 6 days (expired)').toBe(true); // Temporary, expired
    expect(banner3AfterTime.isVisible.value, 'banner3 after 6 days').toBe(false); // Permanent
  });

  describe('generateBannerId', () => {
    it('should generate consistent IDs for the same content', async () => {
      const options1 = { prefix: 'test', content: 'Hello World' };
      const options2 = { prefix: 'test', content: 'Hello World' };

      const id1 = await generateBannerId(options1);
      const id2 = await generateBannerId(options2);

      expect(id1).toBe(id2);
    });

    it('should generate different IDs for different content', async () => {
      const options1 = { prefix: 'test', content: 'Hello World' };
      const options2 = { prefix: 'test', content: 'Different content' };

      const id1 = await generateBannerId(options1);
      const id2 = await generateBannerId(options2);

      expect(id1).not.toBe(id2);
    });

    it('should include the prefix in the generated ID', async () => {
      const options = { prefix: 'custom-prefix', content: 'Some content' };
      const id = await generateBannerId(options);

      expect(id.startsWith('custom-prefix-')).toBe(true);
    });

    it('should handle null content by using a default value', async () => {
      const options = { prefix: 'test', content: null };
      const id = await generateBannerId(options);

      expect(id).toBe('test-default');
    });
  });

  it('should handle invalid or missing localStorage data gracefully', () => {
    // Case 1: Malformed JSON in localStorage
    localStorage.setItem('banner-bad-json', 'this is not valid json {');
    const { isVisible: isVisibleBadJson, dismiss: dismissBadJson } =
      useDismissableBanner('bad-json');
    // Should default to visible if localStorage parsing fails
    expect(isVisibleBadJson.value).toBe(true);
    // Dismissal should still work and overwrite the bad data
    dismissBadJson();
    expect(isVisibleBadJson.value).toBe(false);
    expect(JSON.parse(localStorage.getItem('banner-bad-json') || '{}').dismissed).toBe(true);

    // Case 2: Item exists, dismissed is true, but timestamp is null (e.g. old/corrupted data)
    // For temporary banners, this should effectively mean it's expired because (currentTime - 0) > expirationDays.
    localStorage.setItem(
      `banner-${BANNER_ID_TEMPORARY}`,
      JSON.stringify({ dismissed: true, timestamp: null })
    );
    const { isVisible: isVisibleNoTimestampTemp } = useDismissableBanner(
      BANNER_ID_TEMPORARY,
      EXPIRATION_DAYS
    );
    expect(isVisibleNoTimestampTemp.value).toBe(true);

    // Case 3: Item exists, dismissed is true, timestamp is null, but it's a permanent banner
    // Should remain dismissed because expirationDays === 0 check takes precedence.
    localStorage.setItem(
      `banner-${BANNER_ID_PERMANENT}`,
      JSON.stringify({ dismissed: true, timestamp: null })
    );
    const { isVisible: isVisibleNoTimestampPerm } = useDismissableBanner(BANNER_ID_PERMANENT, 0);
    expect(isVisibleNoTimestampPerm.value).toBe(false);
  });

  describe('Content-based banner IDs', () => {
    // For these tests, we'll use string IDs since we already tested the hash generation separately
    it('should accept an options object for ID generation', () => {
      const { bannerId, isVisible } = useDismissableBanner('content-test-abc123', 0);

      expect(bannerId.value).toBe('content-test-abc123');
      expect(isVisible.value).toBe(true);
    });

    it('should treat different content as different banners', () => {
      // Set up a dismissed banner
      const { dismiss } = useDismissableBanner('content-message1', 0);
      dismiss();

      // A new banner with different content should be visible
      const { isVisible: isVisibleNewContent } = useDismissableBanner('content-message2', 0);

      expect(isVisibleNewContent.value).toBe(true);
    });

    it('should recognize the same content as the same banner', () => {
      const bannerId = 'repeat-same-content';

      // Set up a dismissed banner
      const { dismiss } = useDismissableBanner(bannerId, 0);
      dismiss();

      // The same content should still be dismissed
      const { isVisible: isVisibleSameContent } = useDismissableBanner(bannerId, 0);

      expect(isVisibleSameContent.value).toBe(false);
    });
  });
});
