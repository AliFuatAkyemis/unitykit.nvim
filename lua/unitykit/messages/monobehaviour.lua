-- MonoBehaviour message signatures and one-line Turkish descriptions.
return {
  -- Lifecycle
  { name = "Awake", doc = "Betik örneği yüklendiğinde, Start'tan önce bir kez çağrılır." },
  { name = "OnEnable", doc = "Bileşen etkinleştirildiğinde çağrılır." },
  { name = "Start", doc = "İlk karede, Update'ten önce bir kez çağrılır." },
  { name = "FixedUpdate", doc = "Sabit fizik adımında çağrılır." },
  { name = "Update", doc = "Her karede bir kez çağrılır." },
  { name = "LateUpdate", doc = "Her karede Update bittikten sonra çağrılır." },
  { name = "OnDisable", doc = "Bileşen devre dışı bırakıldığında çağrılır." },
  { name = "OnDestroy", doc = "Bileşen yok edilirken çağrılır." },
  {
    name = "OnValidate",
    doc = "Inspector'da değer değiştiğinde veya betik yeniden yüklendiğinde çağrılır.",
  },
  { name = "Reset", doc = "Bileşen Inspector'da sıfırlandığında çağrılır." },

  -- Physics
  {
    name = "OnCollisionEnter",
    params = "Collision collision",
    doc = "Çarpışma başladığında çağrılır.",
  },
  {
    name = "OnCollisionStay",
    params = "Collision collision",
    doc = "Çarpışma sürerken her fizik adımında çağrılır.",
  },
  {
    name = "OnCollisionExit",
    params = "Collision collision",
    doc = "Çarpışma bittiğinde çağrılır.",
  },
  {
    name = "OnTriggerEnter",
    params = "Collider other",
    doc = "Tetikleyici alana girildiğinde çağrılır.",
  },
  {
    name = "OnTriggerStay",
    params = "Collider other",
    doc = "Tetikleyici alanın içinde kalındıkça çağrılır.",
  },
  {
    name = "OnTriggerExit",
    params = "Collider other",
    doc = "Tetikleyici alandan çıkıldığında çağrılır.",
  },
  {
    name = "OnControllerColliderHit",
    params = "ControllerColliderHit hit",
    doc = "CharacterController bir collider'a çarptığında çağrılır.",
  },
  {
    name = "OnParticleCollision",
    params = "GameObject other",
    doc = "Parçacık bir collider'a çarptığında çağrılır.",
  },

  -- Mouse
  { name = "OnMouseEnter", doc = "Fare nesnenin üzerine geldiğinde çağrılır." },
  { name = "OnMouseOver", doc = "Fare nesnenin üzerindeyken her karede çağrılır." },
  { name = "OnMouseExit", doc = "Fare nesnenin üzerinden ayrıldığında çağrılır." },
  { name = "OnMouseDown", doc = "Fare düğmesine nesne üzerinde basıldığında çağrılır." },
  { name = "OnMouseUp", doc = "Basılı fare düğmesi nesne üzerinde bırakıldığında çağrılır." },
  {
    name = "OnMouseUpAsButton",
    doc = "Aynı nesne üzerinde basılıp bırakılan fare düğmesi için çağrılır.",
  },
  { name = "OnMouseDrag", doc = "Fare düğmesi basılıyken sürüklendiğinde çağrılır." },

  -- Visual / UI
  { name = "OnGUI", doc = "Her GUI olayında çağrılır." },
  { name = "OnDrawGizmos", doc = "Sahne görünümünde gizmo çizimi için her karede çağrılır." },
  { name = "OnDrawGizmosSelected", doc = "Nesne seçiliyken gizmo çizimi için çağrılır." },
  { name = "OnBecameVisible", doc = "Nesne bir kamera tarafından görünür olduğunda çağrılır." },
  {
    name = "OnBecameInvisible",
    doc = "Nesne artık hiçbir kamera tarafından görünmediğinde çağrılır.",
  },

  -- Application
  {
    name = "OnApplicationFocus",
    params = "bool hasFocus",
    doc = "Uygulama odak kazandığında veya kaybettiğinde çağrılır.",
  },
  {
    name = "OnApplicationPause",
    params = "bool pauseStatus",
    doc = "Uygulama duraklatıldığında veya devam ettiğinde çağrılır.",
  },
  { name = "OnApplicationQuit", doc = "Uygulama kapanmadan önce çağrılır." },

  -- Transform
  { name = "OnTransformChildrenChanged", doc = "Alt nesne listesi değiştiğinde çağrılır." },
  { name = "OnTransformParentChanged", doc = "Üst nesne değiştiğinde çağrılır." },

  -- Audio
  {
    name = "OnAudioFilterRead",
    params = "float[] data, int channels",
    doc = "Ses filtresi iş parçacığında ses verisi işlenirken çağrılır.",
  },
}
