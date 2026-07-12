import { Fragment, memo, type ReactNode } from "react";
import ReactMarkdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";

// Citation markers ([1], [2], ...) the model emits inline, referencing the
// numbered Sources list rendered below the answer. Markdown link syntax
// (`[text](url)`) is parsed by remark into a real link node *before* any text
// ever reaches these components, so a plain string child here can only be
// literal bracket text — linkifying it can't clobber `[text](url)` links.
const CITATION_RE = /\[(\d+)\]/g;

function linkifyCitations(children: ReactNode): ReactNode {
  return (Array.isArray(children) ? children : [children]).map((child, i) => {
    if (typeof child !== "string" || !CITATION_RE.test(child)) return child;
    CITATION_RE.lastIndex = 0;
    const parts: ReactNode[] = [];
    let last = 0;
    let match: RegExpExecArray | null;
    while ((match = CITATION_RE.exec(child))) {
      if (match.index > last) parts.push(child.slice(last, match.index));
      const n = match[1];
      parts.push(
        <sup key={`${i}-${match.index}`}>
          <a
            href={`#source-${n}`}
            className="font-medium text-primary no-underline hover:underline"
          >
            [{n}]
          </a>
        </sup>,
      );
      last = match.index + match[0].length;
    }
    if (last < child.length) parts.push(child.slice(last));
    return <Fragment key={i}>{parts}</Fragment>;
  });
}

// Element styling for assistant markdown, tuned to the editorial chat type
// scale and the calm-teal tokens. Block code resets the inline-code styling
// (react-markdown v10 no longer passes an `inline` flag, so we scope via CSS:
// `pre` clears the background/padding its nested `code` would otherwise get).
// Citation linkifying is applied only to prose-bearing elements (not `code`/
// `pre`), so `[3]` inside a code block (e.g. `arr[3]`) is left alone.
const components: Components = {
  p: ({ children }) => <p className="leading-7 [&:not(:first-child)]:mt-3">{linkifyCitations(children)}</p>,
  strong: ({ children }) => <strong className="font-semibold text-foreground">{linkifyCitations(children)}</strong>,
  em: ({ children }) => <em className="italic">{linkifyCitations(children)}</em>,
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
  li: ({ children }) => <li className="leading-7">{linkifyCitations(children)}</li>,
  h1: ({ children }) => <h1 className="mb-2 mt-5 font-display text-xl font-semibold tracking-tight first:mt-0">{children}</h1>,
  h2: ({ children }) => <h2 className="mb-2 mt-5 font-display text-lg font-semibold tracking-tight first:mt-0">{children}</h2>,
  h3: ({ children }) => <h3 className="mb-1.5 mt-4 text-base font-semibold first:mt-0">{children}</h3>,
  h4: ({ children }) => <h4 className="mb-1 mt-3 text-sm font-semibold uppercase tracking-wide text-muted-foreground first:mt-0">{children}</h4>,
  blockquote: ({ children }) => (
    <blockquote className="my-3 border-l-2 border-border pl-3 italic text-muted-foreground">{linkifyCitations(children)}</blockquote>
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
  th: ({ children }) => <th className="border px-3 py-1.5 text-left font-semibold">{linkifyCitations(children)}</th>,
  td: ({ children }) => <td className="border px-3 py-1.5">{linkifyCitations(children)}</td>,
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
