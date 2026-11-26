"use client";

import Link from "next/link";
import { useState } from "react";

const navLinks = [
  { href: "/our-story", label: "Our story" },
  { href: "/products", label: "Products" },
  { href: "/media", label: "Media" },
];

export default function Header() {
  const [open, setOpen] = useState(false);

  return (
    <header className="w-full bg-globo-header">
      <div className="mx-auto flex h-18 max-w-292.5 items-center justify-between px-4 md:h-22.5">
        <div className="flex items-center">
          <Link
            href="/"
            className="border-globo-mint pr-4 text-lg font-semibold text-globo-mint transition hover:text-white"
          >
            Home
          </Link>
        </div>

        <div className="hidden flex-1 items-center justify-center md:flex">
          <nav>
            <ul className="flex items-center">
              {navLinks.map((link) => (
                <li key={link.label}>
                  <Link
                    href={link.href}
                    className="block px-3.25 py-3.75 text-sm text-globo-mint transition hover:text-white"
                  >
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        </div>

        <div className="hidden items-center md:flex">
          <span className="mr-6 h-13 border-globo-mint" />
          <Link
            href="/admin/login"
            className="text-sm font-medium text-globo-mint transition hover:text-white"
          >
            Login
          </Link>
        </div>

        <button
          type="button"
          aria-label="Toggle menu"
          className="flex h-9 w-10 flex-col items-center justify-center gap-1.25 md:hidden"
          onClick={() => setOpen((v) => !v)}
        >
          <span
            className={`block h-0.5 w-5.5 bg-white transition ${
              open ? "translate-y-1.75 rotate-45" : ""
            }`}
          />
          <span
            className={`block h-0.5 w-5.5 bg-white transition ${
              open ? "opacity-0" : ""
            }`}
          />
          <span
            className={`block h-0.5 w-5.5 bg-white transition ${
              open ? "-translate-y-1.75 -rotate-45" : ""
            }`}
          />
        </button>
      </div>

      {open && (
        <div className="border-t border-white/20 py-5 md:hidden">
          <nav>
            <ul className="flex flex-col items-center">
              {navLinks.map((link) => (
                <li key={link.label}>
                  <Link
                    href={link.href}
                    className="block px-3.25 py-3.75 text-sm text-globo-mint transition hover:text-white"
                    onClick={() => setOpen(false)}
                  >
                    {link.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
        </div>
      )}
    </header>
  );
}
