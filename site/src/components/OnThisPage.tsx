export function OnThisPage({ items }: { items: { id: string; label: string }[] }) {
  return (
    <div className="toc">
      <h4 className="toc__title">On This Page</h4>
      <ul className="toc__list">
        {items.map((item) => (
          <li key={item.id}>
            <a href={`#${item.id}`}>{item.label}</a>
          </li>
        ))}
      </ul>
    </div>
  );
}
