// Obsidian의 앱 수명주기 대신 native 파일 색인을 주입한다.
export const PathFilters = { markdown: (path: string) => path.endsWith('.md'), csv: (path: string) => path.endsWith('.csv') };
