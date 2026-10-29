import type { APIRoute } from 'astro';
import { publicSubmissionDisabledResponse } from '../../lib/server/publicSubmissionDisabled.ts';

/** Public submissions are postponed for the personal-use first release; this returns before request or storage access. */
export const POST: APIRoute = () => publicSubmissionDisabledResponse();
