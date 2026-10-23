-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "email" TEXT,
    "phone" TEXT,
    "passwordHash" TEXT NOT NULL,
    "nickname" TEXT,
    "avatarUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Tab" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "artist" TEXT,
    "category" TEXT NOT NULL DEFAULT 'guitar',
    "difficulty" INTEGER NOT NULL DEFAULT 0,
    "style" INTEGER,
    "key" TEXT,
    "tuning" TEXT,
    "sheetForm" INTEGER NOT NULL DEFAULT 0,
    "bpm" INTEGER,
    "timeSig" TEXT,
    "capo" INTEGER NOT NULL DEFAULT 0,
    "tuningText" TEXT,
    "heat" INTEGER NOT NULL DEFAULT 0,
    "uploader" TEXT,
    "publishDate" TIMESTAMP(3),
    "scoreUrl" TEXT NOT NULL,
    "screenshotUrl" TEXT,
    "description" TEXT,
    "tags" TEXT NOT NULL DEFAULT '[]',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Tab_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Favorite" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "tabId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Favorite_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UploadRecord" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "title" TEXT NOT NULL,
    "artist" TEXT,
    "fileName" TEXT NOT NULL,
    "scoreUrl" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UploadRecord_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Article" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "category" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Article_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_phone_key" ON "User"("phone");

-- CreateIndex
CREATE INDEX "Tab_category_difficulty_sheetForm_idx" ON "Tab"("category", "difficulty", "sheetForm");

-- CreateIndex
CREATE INDEX "Tab_category_heat_idx" ON "Tab"("category", "heat");

-- CreateIndex
CREATE INDEX "Tab_category_createdAt_idx" ON "Tab"("category", "createdAt");

-- CreateIndex
CREATE INDEX "Tab_artist_idx" ON "Tab"("artist");

-- CreateIndex
CREATE INDEX "Tab_title_idx" ON "Tab"("title");

-- CreateIndex
CREATE UNIQUE INDEX "Favorite_userId_tabId_key" ON "Favorite"("userId", "tabId");

-- AddForeignKey
ALTER TABLE "Favorite" ADD CONSTRAINT "Favorite_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Favorite" ADD CONSTRAINT "Favorite_tabId_fkey" FOREIGN KEY ("tabId") REFERENCES "Tab"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UploadRecord" ADD CONSTRAINT "UploadRecord_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
