-- Every CPSC recall MUST carry a public URL -- if an engineer can't link back
-- to the regulator, the row is useless for a DFMEA. Returns offending rows
-- (expected: zero).

select record_id, title, url
from {{ ref('stg_cpsc_recalls') }}
where url is null
   or url = ''
   or url not like 'http%'
