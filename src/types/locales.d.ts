type JSONValue = string | number | boolean | { [key: string]: JSONValue } | JSONValue[];

declare module '*.json' {
  const value: { [key: string]: JSONValue }
  export default value
}
