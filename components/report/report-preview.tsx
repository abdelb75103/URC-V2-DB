"use client";

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Download } from "lucide-react";
import { pdf } from "@react-pdf/renderer";
import { Document, Page, pdfjs } from "react-pdf";
import "react-pdf/dist/Page/TextLayer.css";
import { Button } from "@/components/ui/button";
import { ReportDocument, enabledReportSections, type ReportModel, type ReportSectionId } from "@/components/report/report-document";

pdfjs.GlobalWorkerOptions.workerSrc = new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url).toString();

type ReportPreviewProps = {
  model: ReportModel;
  enabledSectionIds?: readonly ReportSectionId[];
  fileName?: string;
  sectionControls?: ReactNode;
  renderPageAction?: (page: ReportPreviewPage) => ReactNode;
  onPreviewReady?: () => void;
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

export function ReportPreview({ model, enabledSectionIds, fileName, sectionControls, renderPageAction, onPreviewReady }: ReportPreviewProps) {
  const sections = useMemo(() => enabledReportSections(enabledSectionIds), [enabledSectionIds]);
  const generationKey = useMemo(() => ({ model, sectionIds: sections.join(",") }), [model, sections]);
  const downloadFileName = fileName ?? defaultReportFileName(model);
  const [renderedPdf, setRenderedPdf] = useState<{ key: typeof generationKey; url: string } | null>(null);
  const [loadedPreview, setLoadedPreview] = useState<{ key: typeof generationKey; pageCount: number } | null>(null);
  const [previewWidth, setPreviewWidth] = useState(595);
  const [generationError, setGenerationError] = useState<{ key: typeof generationKey; message: string } | null>(null);
  const previewFrameRef = useRef<HTMLDivElement>(null);
  const generationKeyRef = useRef(generationKey);
  const generationQueueRef = useRef<Promise<void>>(Promise.resolve());
  generationKeyRef.current = generationKey;

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
    let timer: number | null = null;
    setRenderedPdf(null);
    setLoadedPreview(null);
    setGenerationError(null);
    if (!sections.length) return () => { active = false; };
    timer = window.setTimeout(() => {
      generationQueueRef.current = generationQueueRef.current.then(async () => {
        if (!active) return;
        try {
          const blob = await pdf(<ReportDocument model={model} enabledSectionIds={sections} />).toBlob();
          if (!active) return;
          url = URL.createObjectURL(blob);
          setRenderedPdf({ key: generationKey, url });
        } catch {
          if (active) setGenerationError({ key: generationKey, message: "The report could not be generated." });
        }
      });
    }, 150);
    return () => {
      active = false;
      if (timer) window.clearTimeout(timer);
      if (url) URL.revokeObjectURL(url);
    };
  }, [generationKey, model, sections]);

  const currentPdf = renderedPdf?.key === generationKey ? renderedPdf : null;
  const pageCount = loadedPreview?.key === generationKey ? loadedPreview.pageCount : 0;
  const error = generationError?.key === generationKey ? generationError.message : null;

  function download() {
    if (!currentPdf) return;
    const link = window.document.createElement("a");
    link.href = currentPdf.url;
    link.download = downloadFileName;
    link.hidden = true;
    window.document.body.appendChild(link);
    link.click();
    link.remove();
  }

  const empty = sections.length === 0;
  const generating = !empty && !currentPdf && !error;
  const loadingPreview = !empty && !error && (!currentPdf || pageCount === 0);
  const status = empty
    ? "0 pages. Restore a section to generate a preview."
    : generating || loadingPreview
      ? `Generating ${sections.length}-page report...`
      : error ?? `${pageCount}-page PDF ready to export. Scroll to review.`;
  const previewPages = reportPreviewPages(sections).slice(0, pageCount);
  return <section className="min-h-[calc(100vh-13rem)] rounded-xl border border-border bg-muted/20 p-3 sm:p-5" aria-label="PDF report preview">
    <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
      <p id="report-preview-status" role="status" aria-live="polite" aria-atomic="true" className="text-sm text-muted-foreground">{status}</p>
      <Button type="button" onClick={download} disabled={!currentPdf || loadingPreview} aria-describedby="report-preview-status" className="min-h-11 gap-2"><Download className="size-4" aria-hidden="true" />Export PDF</Button>
    </div>
    {sectionControls && <div key="section-controls">{sectionControls}</div>}
    {error ? <div className="grid min-h-80 place-items-center rounded-lg border border-destructive/40 bg-background p-6 text-center" role="alert">{error}</div> : <div ref={previewFrameRef} role="region" tabIndex={0} aria-label="Scrollable PDF report pages" aria-busy={generating || loadingPreview} className="min-h-[calc(100vh-22rem)] max-h-[calc(100vh-12rem)] overflow-x-hidden overflow-y-auto rounded-lg border bg-slate-200/70 p-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:p-6">
      {empty ? <div className="grid min-h-80 place-items-center rounded-lg border border-dashed bg-background p-6 text-center"><div><p className="font-medium">No report sections selected</p><p className="mt-1 text-sm text-muted-foreground">Restore a section above to generate the PDF preview.</p></div></div> : currentPdf ? <Document file={currentPdf.url} loading={<p className="py-24 text-center text-sm text-muted-foreground">Loading preview...</p>} error={<p className="py-24 text-center text-sm text-destructive">The preview could not be loaded.</p>} onLoadSuccess={({ numPages }) => { if (generationKeyRef.current !== generationKey) return; setLoadedPreview({ key: generationKey, pageCount: numPages }); window.requestAnimationFrame(() => { if (generationKeyRef.current === generationKey) onPreviewReady?.(); }); }} className="w-full"><div className="flex flex-col items-center gap-4">{previewPages.map((page) => (
          <div key={page.sectionId} className="relative max-w-full"><Page pageNumber={page.pageNumber} width={previewWidth} renderAnnotationLayer={false} className="max-w-full shadow-xl">{renderPageAction && <div key={`${page.sectionId}-action`} className="absolute right-2 top-2 z-10 lg:-right-24">{renderPageAction(page)}</div>}</Page></div>
        ))}</div></Document> : <p className="py-24 text-center text-sm text-muted-foreground">Generating report...</p>}
    </div>}</section>;
}
