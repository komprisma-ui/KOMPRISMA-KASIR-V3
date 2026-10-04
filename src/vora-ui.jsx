export const Head=({eyebrow,title,desc,action})=><div className="pageHead"><div><span className="eyebrow">{eyebrow}</span><h1>{title}</h1><p>{desc}</p></div>{action}</div>;
export const PanelHead=({title,sub,right})=><div className="panelHead"><div><h2>{title}</h2><small>{sub}</small></div>{right&&<span className="panelTag">{right}</span>}</div>;
export function Metric({icon:I,label,value,note,danger}){return <div className="metric"><div className={danger?"metricIcon danger":"metricIcon"}><I size={18}/></div><div><span>{label}</span><strong>{value}</strong><small>{note}</small></div></div>}
