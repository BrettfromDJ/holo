-- The Poof cut-outs didn't look good enough; sealed products show their original photos.
-- (Empty the `cutouts` storage bucket in the dashboard to delete the stored images.)
alter table products drop column if exists cutout_url;
