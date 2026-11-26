import { NextResponse } from "next/server";
import { requireAdmin } from "@/lib/api-auth";
import { seedDatabase } from "@/scripts/seed";

export async function POST() {
  const { error } = await requireAdmin();
  if (error) return error;

  try {
    await seedDatabase();
    return NextResponse.json({ ok: true });
  } catch (error) {
    console.error("Seed failed:", error);
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Failed to seed data.",
      },
      { status: 500 },
    );
  }
}
