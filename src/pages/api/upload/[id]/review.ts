import type { APIRoute } from 'astro';
import { publicSubmissionDisabledResponse } from '../../../../lib/server/publicSubmissionDisabled.ts';

/** Self-review and public approval are disabled; do not inspect requests or touch files/database. */
export const POST: APIRoute = () => publicSubmissionDisabledResponse();
