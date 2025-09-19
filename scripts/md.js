import fs from 'node:fs/promises'
import rehypeStringify from 'rehype-stringify'
import remarkParse from 'remark-parse'
import remarkRehype from 'remark-rehype'
import { unified } from 'unified'

const document = await fs.readFile('example.md', 'utf8')

const file = await unified()
  .use(remarkParse)
  .use(remarkRehype)
  .use(rehypeStringify).process(document)

console.log(String(file))