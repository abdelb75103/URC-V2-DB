import type { Metadata } from "next";
import "./styles.css";

export const metadata: Metadata = {
  title: "URC SCRIIPT V2",
  description: "Aggregate injury surveillance dashboard spine"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
