// src/tests/team-schema.spec.ts
import { describe, it, expect } from 'vitest';
import { teamWithRoleSchema } from '@/schemas/models/team';
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
      members: [
        {
          custid: '019a8e52-eea1-7335-9c5e-e10442240d49',
          email: 'test1@example.com',
          role: 'owner',
        },
      ],
    };

    const result = teamWithRoleSchema.safeParse(apiResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.identifier).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
      expect(result.data.objid).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
      expect(result.data.extid).toBe('tm401icu432tjkdb0dmze8iqhqhqc');
      expect(result.data.display_name).toBe('Default Team');
      expect(result.data.description).toBeNull();
      expect(result.data.is_default).toBeNull(); // is_default can be null
      expect(result.data.current_user_role).toBe('owner');
      expect(result.data.members).toHaveLength(1);
      expect(result.data.members?.[0].custid).toBe('019a8e52-eea1-7335-9c5e-e10442240d49');
      expect(result.data.members?.[0].email).toBe('test1@example.com');
      expect(result.data.members?.[0].role).toBe('owner');
      expect(result.data.created).toBeInstanceOf(Date);
      expect(result.data.updated).toBeInstanceOf(Date);
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
      expect(result.data.records[0].identifier).toBe('019a905e-dc91-7264-ba63-5b875b0b7939');
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
      members: [
        {
          custid: '019a8e52-eea1-7335-9c5e-e10442240d49',
          email: 'test1@example.com',
          role: 'admin',
        },
        {
          custid: '019a8e52-eea1-7335-9c5e-e10442240d50',
          email: 'test2@example.com',
          role: 'member',
        },
      ],
    };

    const result = teamWithRoleSchema.safeParse(apiResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.description).toBe('Our awesome engineering team');
      expect(result.data.is_default).toBe(true);
      expect(result.data.member_count).toBe(5);
      expect(result.data.current_user_role).toBe('admin');
      expect(result.data.members).toHaveLength(2);
      expect(result.data.members?.[0].role).toBe('admin');
      expect(result.data.members?.[1].role).toBe('member');
    }
  });

  it('should handle team without members field', () => {
    const apiResponse = {
      identifier: '019a905e-dc91-7264-ba63-5b875b0b7939',
      objid: '019a905e-dc91-7264-ba63-5b875b0b7939',
      extid: 'tm401icu432tjkdb0dmze8iqhqhqc',
      display_name: 'Marketing Team',
      description: null,
      owner_id: '019a8e52-eea1-7335-9c5e-e10442240d49',
      org_id: '019a905e-dc85-7a0c-8a1b-598262f3d1d8',
      is_default: null,
      member_count: 3,
      updated: 1763358727.31295,
      created: 1763358727.31295,
      current_user_role: 'member',
    };

    const result = teamWithRoleSchema.safeParse(apiResponse);

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.display_name).toBe('Marketing Team');
      expect(result.data.current_user_role).toBe('member');
      expect(result.data.members).toBeUndefined();
    }
  });
});
