-- Keep existing rows and scores intact while matching the current Prisma model.
ALTER TABLE "Tab"
  ALTER COLUMN "scoreUrl" DROP NOT NULL;

ALTER TABLE "Tab"
  ADD COLUMN "format" TEXT NOT NULL DEFAULT 'gp',
  ADD COLUMN "xheUrl" TEXT;
