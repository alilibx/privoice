import { memo } from "react";
import ReactMarkdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";

// Element styling for assistant markdown, tuned to the editorial chat type
// scale and the calm-teal tokens. Block code resets the inline-code styling
// (react-markdown v10 no longer passes an `inline` flag, so we scope via CSS:
// `pre` clears the background/padding its nested `code` would otherwise get).
const components: Components = {
  p: ({ children }) => <p className="leading-7 [&:not(:first-child)]:mt-3">{children}</p>,
  strong: ({ children }) => <strong className="font-semibold text-foreground">{children}</strong>,
  em: ({ children }) => <em className="italic">{children}</em>,
  a: ({ children, href }) => (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="font-medium text-primary underline underline-offset-2 hover:no-underline"
    >
      {children}
    </a>
  ),
  ul: ({ children }) => <ul className="my-3 list-disc space-y-1.5 pl-5 marker:text-muted-foreground">{children}</ul>,
  ol: ({ children }) => <ol className="my-3 list-decimal space-y-1.5 pl-5 marker:text-muted-foreground">{children}</ol>,
  li: ({ children }) => <li className="leading-7">{children}</li>,
  h1: ({ children }) => <h1 className="mb-2 mt-5 font-display text-xl font-semibold tracking-tight first:mt-0">{children}</h1>,
  h2: ({ children }) => <h2 className="mb-2 mt-5 font-display text-lg font-semibold tracking-tight first:mt-0">{children}</h2>,
  h3: ({ children }) => <h3 className="mb-1.5 mt-4 text-base font-semibold first:mt-0">{children}</h3>,
  h4: ({ children }) => <h4 className="mb-1 mt-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground first:mt-0">{children}</h4>,
  blockquote: ({ children }) => (
    <blockquote className="my-3 border-l-2 border-border pl-3 italic text-muted-foreground">{children}</blockquote>
  ),
  hr: () => <hr className="my-4 border-border" />,
  code: ({ children }) => (
    <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-[13px]">{children}</code>
  ),
  pre: ({ children }) => (
    <pre className="my-3 overflow-x-auto rounded-lg border bg-muted/60 p-3 text-[13px] leading-relaxed [&_code]:bg-transparent [&_code]:p-0">
      {children}
    </pre>
  ),
  table: ({ children }) => (
    <div className="my-3 overflow-x-auto">
      <table className="w-full border-collapse text-sm">{children}</table>
    </div>
  ),
  th: ({ children }) => <th className="border px-3 py-1.5 text-left font-semibold">{children}</th>,
  td: ({ children }) => <td className="border px-3 py-1.5">{children}</td>,
};

function MarkdownImpl({ children }: { children: string }) {
  return (
    <div className="text-[15px] leading-7 text-foreground">
      <ReactMarkdown remarkPlugins={[remarkGfm]} components={components}>
        {children}
      </ReactMarkdown>
    </div>
  );
}

// Memoized so streaming re-renders of the parent don't re-parse unchanged text.
export default memo(MarkdownImpl);
