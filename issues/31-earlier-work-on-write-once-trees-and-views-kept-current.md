# What earlier work stands behind write-once trees and views kept current?

Type: research
Status: resolved

## Question

design-ideas.md proposes storing the database as a tree of write-once nodes named by the hash of their contents, storing code by hash, and treating an index as a view the database keeps current. Find the strongest earlier work on each, the costs measured, and which kinds of function a system can keep current by itself.

## Answer

The storage shape is proven at the scale of a terabyte by Dolt, with three warnings. Garbage grows fast and every kept version holds it in place: one Datomic user reached over 900 GB on disk for about 40 GB of live data, and Dolt reports about 500 GB of garbage a week on a 650 GB database. History named by hashes pulls against erasing a person's data. Views written as arbitrary code cannot be kept current cheaply; maps, filters, joins and reduces that can be undone can. To copy: Dolt's tree written once per batch, and CouchDB's contract for views. Findings: [research/31-earlier-work-on-write-once-trees-and-views-kept-current.md](../research/31-earlier-work-on-write-once-trees-and-views-kept-current.md).
