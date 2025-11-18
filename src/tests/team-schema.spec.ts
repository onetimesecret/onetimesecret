// src/tests/team-schema.spec.ts
import { describe, it, expect } from 'vitest';
import { teamWithRoleSchema } from '@/types/team';
import { teamsResponseSchema } from '@/schemas/api/teams/endpoints/teams';

describe('Team Schema Validation', () => {
  it('should validate team API response with null values', () => {
    const apiResponse = {
      identifier: '019a905e-dc91-7264-ba63-5b875b0b7939',
      objid: '019a905e-dc91-7264-ba63-5b875b0b7939',
      extid: 'tm401icu432tjkdb0dmze8iqhqhqc',
      display_name: 'Default Team',
      description: null,
      owner_id: '019a8e52-eea1-7335-9c5e-e10442240d49',
      org_id: '019a905e-dc85-7a0c-8a1b-598262f3d1d8',
      is_default: null,
      member_count: 1,
      updated: 1763358727.31295,
      created: 1763358727.31295,
      current_user_role: 'owner',
    };

    const result = teamWithRoleSchema.safeParse(apiResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.id).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
      expect(result.data.identifier).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
      expect(result.data.objid).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
      expect(result.data.extid).toBe('tm401icu432tjkdb0dmze8iqhqhqc');
      expect(result.data.display_name).toBe('Default Team');
      expect(result.data.description).toBeUndefined();
      expect(result.data.is_default).toBe(false); // null should become false
      expect(result.data.current_user_role).toBe('owner');
      expect(result.data.created_at).toBeInstanceOf(Date);
      expect(result.data.updated_at).toBeInstanceOf(Date);
    }
  });

  it('should validate teams list API response', () => {
    const apiResponse = {
      user_id: '019a8e52-eea1-7335-9c5e-e10442240d49',
      records: [
        {
          identifier: '019a905e-dc91-7264-ba63-5b875b0b7939',
          objid: '019a905e-dc91-7264-ba63-5b875b0b7939',
          extid: 'tm401icu432tjkdb0dmze8iqhqhqc',
          display_name: 'Default Team',
          description: null,
          owner_id: '019a8e52-eea1-7335-9c5e-e10442240d49',
          org_id: '019a905e-dc85-7a0c-8a1b-598262f3d1d8',
          is_default: null,
          member_count: 1,
          updated: 1763358727.31295,
          created: 1763358727.31295,
          current_user_role: 'owner',
        },
      ],
      count: 1,
    };

    const result = teamsResponseSchema.safeParse(apiResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.records).toHaveLength(1);
      expect(result.data.count).toBe(1);
      expect(result.data.records[0].id).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
      expect(result.data.records[0].display_name).toBe('Default Team');
    }
  });

  it('should handle team with all fields populated', () => {
    const apiResponse = {
      identifier: '019a905e-dc91-7264-ba63-5b875b0b7939',
      objid: '019a905e-dc91-7264-ba63-5b875b0b7939',
      extid: 'tm401icu432tjkdb0dmze8iqhqhqc',
      display_name: 'Engineering Team',
      description: 'Our awesome engineering team',
      owner_id: '019a8e52-eea1-7335-9c5e-e10442240d49',
      org_id: '019a905e-dc85-7a0c-8a1b-598262f3d1d8',
      is_default: true,
      member_count: 5,
      updated: 1763358727.31295,
      created: 1763358727.31295,
      current_user_role: 'admin',
    };

    const result = teamWithRoleSchema.safeParse(apiResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.description).toBe('Our awesome engineering team');
      expect(result.data.is_default).toBe(true);
      expect(result.data.member_count).toBe(5);
      expect(result.data.current_user_role).toBe('admin');
    }
  });
});
