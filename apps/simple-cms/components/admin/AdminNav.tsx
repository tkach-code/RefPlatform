"use client";

import { withBasePath } from "@/lib/base-path";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOut } from "next-auth/react";
import { useRef, useState } from "react";

const links = [
  { href: "/admin", label: "Dashboard" },
  { href: "/admin/products", label: "Products" },
  { href: "/admin/categories", label: "Categories" },
  { href: "/admin/media", label: "Media" },
  { href: "/admin/story", label: "Story" },
  { href: "/admin/events", label: "Events" },
  { href: "/admin/page-content", label: "Page Content" },
  { href: "/admin/registrations", label: "Registrations" },
];

export default function AdminNav() {
  const pathname = usePathname();
  const [isSeeding, setIsSeeding] = useState(false);
  const confirmDialogRef = useRef<HTMLDialogElement | null>(null);
  const notificationDialogRef = useRef<HTMLDialogElement | null>(null);
  const [notificationMessage, setNotificationMessage] = useState("");

  const openDialog = (dialogRef: React.RefObject<HTMLDialogElement | null>) => {
    dialogRef.current?.showModal();
  };

  const closeDialog = (dialogRef: React.RefObject<HTMLDialogElement | null>) => {
    dialogRef.current?.close();
  };

  async function handleSeedData() {
    openDialog(confirmDialogRef);
  }

  async function confirmSeedData() {
    closeDialog(confirmDialogRef);
    setIsSeeding(true);

    try {
      const response = await fetch(withBasePath("/api/seed"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
      });

      const payload = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(payload.error || "Unable to seed data.");
      }

      setNotificationMessage("Site data has been reset and seeded successfully.");
      openDialog(notificationDialogRef);
    } catch (error) {
      console.error(error);
      setNotificationMessage(
        error instanceof Error ? error.message : "Failed to seed data.",
      );
      openDialog(notificationDialogRef);
    } finally {
      setIsSeeding(false);
    }
  }

  return (
    <>
      <dialog
        ref={confirmDialogRef}
        className="max-w-md rounded-xl border border-gray-200 bg-white p-0 shadow-xl backdrop:bg-black/30"
      >
        <div className="p-6">
          <h2 className="mb-3 text-lg font-semibold text-gray-900">
            Confirm seed reset
          </h2>
          <p className="text-sm text-gray-600">
            This will delete the current site content and restore the default
            seeded data. Continue?
          </p>
          <div className="mt-6 flex justify-end gap-3">
            <button
              type="button"
              onClick={() => closeDialog(confirmDialogRef)}
              className="rounded border border-gray-300 px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={confirmSeedData}
              className="rounded bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-500"
            >
              Reset &amp; seed
            </button>
          </div>
        </div>
      </dialog>

      <dialog
        ref={notificationDialogRef}
        className="max-w-md rounded-xl border border-gray-200 bg-white p-0 shadow-xl backdrop:bg-black/30"
      >
        <div className="p-6">
          <h2 className="mb-3 text-lg font-semibold text-gray-900">
            Seed status
          </h2>
          <p className="text-sm text-gray-600">{notificationMessage}</p>
          <div className="mt-6 flex justify-end">
            <button
              type="button"
              onClick={() => closeDialog(notificationDialogRef)}
              className="rounded bg-globo-teal px-4 py-2 text-sm font-medium text-white hover:bg-globo-teal-dark"
            >
              Close
            </button>
          </div>
        </div>
      </dialog>

      <aside className="w-56 shrink-0 border-r border-gray-200 bg-white p-4">
        <div className="mb-6">
          <p className="text-xs uppercase tracking-wide text-gray-500">Admin</p>
          <p className="font-semibold text-globo-header">RefPlatform</p>
        </div>
        <nav className="flex flex-col gap-1">
          {links.map((link) => {
            const active =
              link.href === "/admin"
                ? pathname === "/admin"
                : pathname.startsWith(link.href);
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`rounded px-3 py-2 text-sm ${
                  active
                    ? "bg-globo-teal text-white"
                    : "text-gray-700 hover:bg-gray-100"
                }`}
              >
                {link.label}
              </Link>
            );
          })}
        </nav>
        <div className="mt-8 space-y-2">
          <button
            type="button"
            onClick={handleSeedData}
            disabled={isSeeding}
            className="w-full rounded px-3 py-2 text-left text-sm text-gray-700 hover:bg-gray-100 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isSeeding ? "Seeding..." : "Seed data"}
          </button>
          <Link
            href="/"
            className="block rounded px-3 py-2 text-sm text-gray-600 hover:bg-gray-100"
          >
            View site
          </Link>
          <button
            type="button"
            onClick={() => signOut({ callbackUrl: withBasePath("/admin/login") })}
            className="w-full rounded px-3 py-2 text-left text-sm text-red-600 hover:bg-red-50"
          >
            Sign out
          </button>
        </div>
      </aside>
    </>
  );
}
