import './device-frame.css';

export function DeviceFrame({
  src,
  alt,
  caption,
}: {
  src: string;
  alt: string;
  caption?: string;
}) {
  return (
    <figure className="device">
      <div className="device__frame">
        <img src={src} alt={alt} loading="lazy" />
      </div>
      {caption && <figcaption className="device__caption">{caption}</figcaption>}
    </figure>
  );
}
