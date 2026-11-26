import Link from "next/link";

const primaryLinks = [
  { href: "/our-story", label: "Our Story" },  
  { href: "/products", label: "Products" },
  { href: "/media", label: "Media" },  
];

export default function Footer() {
  return (
    <footer className="relative overflow-hidden bg-globo-footer">
      <div className="flex w-full justify-center py-6">
        <ul className="flex list-none items-center justify-center gap-8 md:gap-12">
          {primaryLinks.map((link) => (
            <li key={link.label}>
              <Link
                href={link.href}
                className="text-sm text-globo-gray transition-colors hover:text-white"
              >
                {link.label}
              </Link>
            </li>
          ))}
        </ul>
      </div>
      <p className="pb-6 text-center text-sm text-globo-gray">CMS Demo App 2026 (v0.1.2)</p>
    </footer>
  );
}
