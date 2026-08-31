"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { ChevronLeft, ChevronRight, Download } from "lucide-react";
import { pdf } from "@react-pdf/renderer";
import { Document, Page, pdfjs } from "react-pdf";
import { Button } from "@/components/ui/button";
import { ReportDocument, enabledReportSections, type ReportModel, type ReportSectionId } from "@/components/report/report-document";

pdfjs.GlobalWorkerOptions.workerSrc = new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url).toString();

type ReportPreviewProps = {
  model: ReportModel;
  enabledSectionIds?: readonly ReportSectionId[];
  fileName?: string;
  renderPageAction?: (page: ReportPreviewPage) => ReactNode;
};

export type ReportPreviewPage = { sectionId: ReportSectionId; pageNumber: number };

export function reportPreviewPages(sectionIds?: readonly ReportSectionId[]): ReportPreviewPage[] {
  return enabledReportSections(sectionIds).map((sectionId, index) => ({ sectionId, pageNumber: index + 1 }));
}

export function defaultReportFileName(model: ReportModel): string {
  const subject = model.subjectName.toLocaleLowerCase("en-IE").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "urc";
  const exportDate = /^\d{4}-\d{2}-\d{2}/.test(model.exportedAt) ? model.exportedAt.slice(0, 10) : "export";
  return `${subject}-${model.season}-v${model.reportVersion}-${exportDate}.pdf`;
}

export function ReportPreview({ model, enabledSectionIds, fileName, renderPageAction }: ReportPreviewProps) {
  const sections = useMemo(() => enabledReportSections(enabledSectionIds), [enabledSectionIds]);
  const downloadFileName = fileName ?? defaultReportFileName(model);
  const [blob, setBlob] = useState<Blob | null>(null);
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [pageCount, setPageCount] = useState(0);
  const [pageNumber, setPageNumber] = useState(1);
  const [previewWidth, setPreviewWidth] = useState(595);
  const [error, setError] = useState<string | null>(null);
  const previewFrameRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const frame = previewFrameRef.current;
    if (!frame) return;
    const updateWidth = () => setPreviewWidth(Math.min(595, Math.max(240, frame.clientWidth - 16)));
    updateWidth();
    const observer = new ResizeObserver(updateWidth);
    observer.observe(frame);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    let active = true;
    let url: string | null = null;
    setBlob(null);
    setBlobUrl(null);
    setPageCount(0);
    setPageNumber(1);
    setError(null);
    pdf(<ReportDocument model={model} enabledSectionIds={sections} />).toBlob()
      .then((nextBlob) => {
        if (!active) return;
        url = URL.createObjectURL(nextBlob);
        setBlob(nextBlob);
        setBlobUrl(url);
      })
      .catch(() => active && setError("The report could not be generated."));
    return () => {
      active = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [model, sections]);

  function download() {
    if (!blobUrl || !blob) return;
    const link = window.document.createElement("a");
    link.href = blobUrl;
    link.download = downloadFileName;
    link.click();
  }

  const loading = !blobUrl && !error;
  const currentPage = sections[pageNumber - 1] ? { sectionId: sections[pageNumber - 1], pageNumber } : null;
  return <section className="min-h-[calc(100vh-13rem)] rounded-xl border border-border bg-muted/20 p-3 sm:p-5" aria-label="PDF report preview">
    <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
      <p className="text-sm text-muted-foreground">{loading ? "Generating report..." : error ?? `${sections.length} report sections`}</p>
      <Button type="button" onClick={download} disabled={!blob} className="min-h-11 gap-2"><Download className="size-4" aria-hidden="true" />Export PDF</Button>
    </div>
    {error ? <div className="grid min-h-80 place-items-center rounded-lg border border-destructive/40 bg-background p-6 text-center" role="alert">{error}</div> : <>
      <div ref={previewFrameRef} className="grid min-h-[calc(100vh-22rem)] place-items-center overflow-auto rounded-lg border bg-slate-200/70 p-2 sm:p-6">
        {blobUrl ? <Document file={blobUrl} loading={<p className="text-sm text-muted-foreground">Loading preview...</p>} error={<p className="text-sm text-destructive">The preview could not be loaded.</p>} onLoadSuccess={({ numPages }) => setPageCount(numPages)}><Page pageNumber={pageNumber} width={previewWidth} renderAnnotationLayer={false} renderTextLayer={false} className="max-w-full shadow-xl" /></Document> : <p className="text-sm text-muted-foreground">Generating report...</p>}
      </div>
      <div className="mt-3 flex flex-wrap items-center justify-center gap-3" aria-label="Preview page controls">
        <Button type="button" variant="outline" size="icon" className="size-11" disabled={loading || pageNumber <= 1} onClick={() => setPageNumber((current) => Math.max(1, current - 1))} aria-label="Previous page"><ChevronLeft className="size-5" /></Button>
        <p className="min-w-28 text-center text-sm text-muted-foreground">Page {pageCount ? pageNumber : "-"} of {pageCount || "-"}</p>
        <Button type="button" variant="outline" size="icon" className="size-11" disabled={loading || pageNumber >= pageCount} onClick={() => setPageNumber((current) => Math.min(pageCount, current + 1))} aria-label="Next page"><ChevronRight className="size-5" /></Button>
        {currentPage && renderPageAction?.(currentPage)}
      </div>
    </>}</section>;
}
