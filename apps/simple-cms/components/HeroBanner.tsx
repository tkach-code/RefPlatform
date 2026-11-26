import Image from "next/image";
import { withBasePath } from "@/lib/base-path";
import { ReactNode } from "react";

type Props = {
  image: string;
  children: ReactNode;
  mobileBanner?: boolean;
};

export default function HeroBanner({
  image,
  children,
  mobileBanner = true,
}: Props) {
  return (
    <section
      className={`relative clear-both ${
        mobileBanner
          ? "max-md:h-[460px] max-md:bg-[image:var(--hero-bg)] max-md:bg-cover max-md:bg-center"
          : ""
      }`}
      // CSS url() values don't get the Next.js basePath, so set the URL here.
      style={
        {
          "--hero-bg": `url('${withBasePath("/images/banner.png")}')`,
        } as React.CSSProperties
      }
    >
      <Image
        src={withBasePath(image)}
        alt=""
        width={1920}
        height={700}
        className="relative mx-auto hidden w-full md:block"
        priority
      />
      <div className="absolute inset-0 top-[50px] text-white md:top-[150px]">
        <div className="mx-auto w-full max-w-[1170px] px-4">{children}</div>
      </div>
    </section>
  );
}
