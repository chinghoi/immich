// A disposable tailnet and Immich-shaped HTTP fixture. No real account or keys.
// Compiled inside the pinned libtailscale/tstestcontrol module in cloud CI.
package main

import "C"

import (
 "bytes"
 "context"
 "crypto/ecdsa"
 "crypto/elliptic"
 "crypto/rand"
 "crypto/tls"
 "crypto/x509"
 "crypto/x509/pkix"
 "encoding/base64"
 "encoding/json"
 "fmt"
 "io"
 "math/big"
 "net"
 "net/http"
 "net/http/httptest"
 "os"
 "strings"
 "time"
 "unsafe"

 "github.com/coder/websocket"
 "tailscale.com/tsnet"
 "tailscale.com/types/logger"
)

func main() {
 if len(os.Args) != 2 { panic("output JSON path required") }
 buffer := make([]byte, 4096)
 if RunControl((*C.char)(unsafe.Pointer(&buffer[0])), C.size_t(len(buffer))) != 0 { panic("control failed") }
 controlURL := strings.TrimRight(string(buffer), "\x00")
 dir, err := os.MkdirTemp("", "immich-fixture-node-"); must(err)
 defer os.RemoveAll(dir)
 server := &tsnet.Server{Dir:dir, Hostname:"immich-fixture", ControlURL:controlURL, Logf:logger.Discard}
 ctx, cancel := context.WithTimeout(context.Background(), time.Minute); defer cancel()
 status, err := server.Up(ctx); must(err)
 ip := status.TailscaleIPs[0].String()
 payload := make([]byte, 8192)
 for i := range payload { payload[i] = byte(i % 251) }
 handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
   if r.URL.Path == "/api/auth/login" {
     if r.Method != "POST" { http.Error(w,"method",405); return }
     http.SetCookie(w, &http.Cookie{Name:"immich_access_token",Value:"fixture-only",Path:"/"})
     w.Header().Set("Content-Type","application/json"); fmt.Fprint(w,`{"accessToken":"fixture-only"}`); return
   }
   cookie, _ := r.Cookie("immich_access_token")
   if (cookie == nil || cookie.Value != "fixture-only") && r.Header.Get("Authorization") != "Bearer fixture-only" {
     http.Error(w,"unauthorized",401); return
   }
   switch r.URL.Path {
   case "/api/assets/thumbnail", "/api/assets/original":
     http.ServeContent(w,r,"fixture.bin",time.Unix(0,0),bytes.NewReader(payload))
   case "/api/assets":
     must(r.ParseMultipartForm(1024*1024)); defer r.MultipartForm.RemoveAll()
     f,_,err := r.FormFile("assetData"); if err != nil { http.Error(w,"multipart",400); return }; defer f.Close()
     body,err := io.ReadAll(io.LimitReader(f,1024*1024)); must(err)
     if !bytes.Equal(body,payload) { http.Error(w,"corrupt",400); return }
     w.Header().Set("Content-Type","application/json"); w.WriteHeader(201); fmt.Fprint(w,`{"id":"fixture-asset","bytes":8192}`)
   case "/api/socket":
     ws,err := websocket.Accept(w,r,nil); if err != nil { return }; defer ws.CloseNow()
     typ,data,err := ws.Read(r.Context()); if err == nil { _ = ws.Write(r.Context(),typ,data) }
   case "/api/redirect": http.Redirect(w,r,"/api/assets/original",http.StatusTemporaryRedirect)
   case "/api/slow":
     w.Header().Set("Content-Length","81920")
     for i:=0;i<10;i++ { if _,err:=w.Write(payload); err!=nil{return}; w.(http.Flusher).Flush(); time.Sleep(200*time.Millisecond) }
   default: http.NotFound(w,r)
   }
 })
 plain := httptest.NewServer(handler); defer plain.Close()
 listener,err := server.Listen("tcp",":2283"); must(err)
 go http.Serve(listener,handler)
 key,err := ecdsa.GenerateKey(elliptic.P256(),rand.Reader); must(err)
 template := &x509.Certificate{SerialNumber:big.NewInt(1), Subject:pkix.Name{CommonName:"Disposable CI fixture"},
   NotBefore:time.Now().Add(-time.Minute),NotAfter:time.Now().Add(2*time.Hour),
   IPAddresses:[]net.IP{net.ParseIP(ip),net.ParseIP("127.0.0.1")}, IsCA:true,BasicConstraintsValid:true,
   KeyUsage:x509.KeyUsageDigitalSignature|x509.KeyUsageKeyEncipherment|x509.KeyUsageCertSign,
   ExtKeyUsage:[]x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
 der,err := x509.CreateCertificate(rand.Reader,template,template,&key.PublicKey,key); must(err)
 tlsListener,err := server.Listen("tcp",":2284"); must(err)
 go http.Serve(tls.NewListener(tlsListener,&tls.Config{Certificates:[]tls.Certificate{{Certificate:[][]byte{der},PrivateKey:key}},MinVersion:tls.VersionTLS12}),handler)
 data,err:=json.Marshal(map[string]string{"controlURL":controlURL,"target":"http://"+ip+":2283",
   "tlsTarget":"https://"+ip+":2284","plainTarget":plain.URL,"certificate":base64.StdEncoding.EncodeToString(der)});must(err)
 must(os.WriteFile(os.Args[1],data,0600))
 select{}
}

func must(err error) { if err != nil { panic(err) } }
